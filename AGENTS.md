# AGENTS.md: AirDrop on Linux (omdrop, omdrop-owl, & CachyOS/KDE Port)

## 1. Project Overview & Context

This workspace contains the codebase for running Apple AirDrop natively on Linux. Originally developed for **Omarchy** on Apple Silicon Macs, this project is being ported to **CachyOS** (an Arch-based distribution) on standard PC hardware (Intel Wi-Fi 6E AX211, `iwlwifi`) running **KDE Plasma 6**.

### Core Repositories

1. **`omdrop-owl`**: The radio backend for non-Apple-Broadcom Wi-Fi chipsets. It creates and manages an `awdl0` network interface entirely in userspace using a patched version of [OWL](https://github.com/jedbillyb/owl) over an 802.11 monitor interface (`mon0`).
2. **`omdrop-plugin`**: The user-facing AirDrop implementation. It provides the command-line interface (`omdrop`), HTTPS receiver daemon (`airdrop-serve.py`), contacts verification (`contacts.py`), identity/crypto management (`identity.py`), and desktop integration.

---

## 2. AirDrop & AWDL Architecture on Linux

AirDrop operates over Apple Wireless Direct Link (AWDL), peer-to-peer Wi-Fi, Bluetooth Low Energy (BLE), and HTTPS.

```
+-----------------------------------------------------------------------------------+
|                                 KDE Plasma 6 / Taskbar                            |
|                       (Plasmoid: Compact Icon + Full Panel + Radar)                |
+------------------------------------------+----------------------------------------+
                                           | CLI / IPC
+------------------------------------------v----------------------------------------+
|                                    `omdrop` CLI                                    |
|   (Receiving window timer, settings, sender picker, notification dispatch, setup) |
+---------------------+-------------------------------------+-----------------------+
                      |                                     |
       Controls HTTPS Receiver Service       Controls Radio Discovery Helper
                      |                                     |
+---------------------v----------------+    +---------------v-----------------------+
|  `airdrop-receiver.service` (Systemd)|    |   `/usr/lib/omdrop/omdrop-discoverable`|
|  - `airdrop-serve.py` (port 8771)    |    |   (Runs as root via Polkit/pkexec)    |
|  - Serves: /Discover, /Ask, /Upload  |    +-------------------+-------------------+
|  - Enforces Contacts & Identity      |                        |
+---------------------+----------------+      +-----------------+-------------------+
                      |                       |                                     |
                      |          Binds to   +--v-------------------+  +--------------v------+
                      +-------------------->|  OWL Daemon (userspace|  | BLE Continuity Adv  |
                                            |  Creates `awdl0` over|  | `ble-airdrop-adv.py`|
                                            |  `mon0` on AP channel|  | (BlueZ / D-Bus)     |
                                            +----------------------+  +---------------------+
```

### Protocol Stages:
1. **Discovery (BLE & mDNS / AWDL)**:
   - iPhones periodically listen for AWDL and BLE Continuity frames.
   - To announce presence, Linux broadcasts unsolicited mDNS `_airdrop._tcp` announcements over `awdl0` via `awdl-airdrop-adv.py`.
   - To wake sleeping Apple devices, Linux broadcasts BLE Continuity AirDrop adverts via `ble-airdrop-adv.py` (talking to BlueZ over D-Bus).
2. **Transport (AWDL / IPv6 Link-Local)**:
   - AWDL frames operate on fixed "social" channels: Channel 6 (2.4 GHz, 2437 MHz), Channel 44 (5 GHz, 5220 MHz), and Channel 149 (5 GHz, 5745 MHz).
   - Network communication is IPv6 link-local (`fe80::...`) on interface `awdl0`.
3. **Transfer (HTTPS / Apple Endpoints)**:
   - Port 8771: Receiver HTTPS server (`airdrop-serve.py`).
   - `/Discover`: Apple device probes our identity, display name, and capabilities. Returns TLS cert and Apple ID validation record.
   - `/Ask`: Sender requests permission to transfer files or URL links, providing file metadata and thumbnail.
   - `/Upload`: Sender streams files packed in Apple CPIO / archive format.
4. **Sending**:
   - `send-to-peer` identifies peer link-local addresses from the AWDL peer table.
   - `airdrop-send.py` initiates `/Discover`, `/Ask`, and `/Upload` against peer port 8770/8771.

---

## 3. Deep Dive: `omdrop-owl`

### Purpose
On Apple Silicon, Broadcom Wi-Fi chips handle AWDL in firmware (`brcmfmac`). Standard PC Wi-Fi chips (MediaTek `mt7925e`, Intel `iwlwifi`, etc.) do not have AWDL firmware. `omdrop-owl` replaces the Broadcom kernel driver by running Open Wireless Link (OWL) in userspace.

### Files & Roles
- **`userspace/omdrop-discoverable`**: Root helper executing via `pkexec`.
  - Commands: `start <seconds>`, `stop`, `status [--json]`, `peers`, `probe [--json]`.
  - Creates monitor vif `mon0` using `iw phy <phy> interface add mon0 type monitor`.
  - Detects AP channel (must be 6, 44, or 149).
  - Starts patched `owl` binary with `-i mon0 -c <chan> -S intersect`.
  - Manages `awdl0` link-local IPv6 assignment.
  - Spawns background supervisor broadcasting `awdl-airdrop-adv.py`.
- **`userspace/owl-profiles`**: Driver configuration table defining:
  - `status`: `tested` or `untested`.
  - `mode`: `shared` (shares AP channel while connected) or `exclusive`.
  - `mon_mac`: `station` (re-uses station MAC) or `own` (creates locally administered MAC, tells OWL station MAC via `-m`).
  - `reconnect`: `yes` or `no` (reassociates Wi-Fi after teardown).
  - `mt76_pm`: disables power management for MediaTek cards.
- **`patches/`**:
  - `owl-01-tx-rate.patch`: Allows setting data-frame PHY transmission rate (`-R`).
  - `owl-02-awdl-addr.patch`: Adds `-m MAC` to decouple monitor interface MAC from AWDL address.
- **`tools/build-owl.sh`**: Clones `jedbillyb/owl`, applies patches, builds daemon with CMake.
- **`tools/stage.sh`**: Copies OWL and pulls portable tools from `omdrop-awdl` (`send-to-peer`, `airdrop-send.py`, `ble-airdrop-adv.py`, `awdl-airdrop-adv.py`, etc.) into `build/lib`.
- **`PKGBUILD`**: Arch packaging script installing everything to `/usr/lib/omdrop` with Polkit policy `io.github.t4t5.omdrop-owl.policy` and NetworkManager rule `99-omdrop-owl-unmanaged.conf`.

---

## 4. Deep Dive: `omdrop-plugin`

### Purpose
The user-space coordination layer and desktop client.

### Files & Roles
- **`bin/omdrop`**: Central Bash executable controlling systemd service and state:
  - `on [-c|-e] [DURATION]`: Starts receive window (transient systemd timer).
  - `off [--force]`: Stops receiver and radio helper.
  - `status [--json]`: Returns full JSON state (receiving, visible, remaining seconds, device name, download dir, audience, sender count).
  - `send [NAME] FILE...|URL...`: Sends files/links using `send-to-peer`.
  - `peers [-n] [--json]`: Lists nearby Apple devices.
  - `name`, `dir`, `limit`, `visibility`, `senders`: Configuration handlers.
  - `setup`: Idempotently writes systemd service `airdrop-receiver.service`, links opener `.desktop`, and generates self-signed TLS certs.
- **`bin/airdrop-serve.py`**: HTTPS server implementing Apple AirDrop protocol:
  - Authenticates TLS certificates and Apple ID validation records (`contacts.py`).
  - Verifies disk quota and links.
  - Saves received files to configured download folder.
- **`bin/identity.py`**: Manages TLS identities:
  - Generates self-signed certificates in `~/.omdrop/keys/`.
  - Supports extracting and caching Apple ID identities from disk or 1Password via Linux kernel keyring (`keyutils`).
- **`share/airdrop-receiver.service`**: Systemd user service template for `airdrop-serve.py`.
- **`Panel.qml`, `Radar.qml`, `OmdropIcon.qml`**: Original Omarchy UI written in Quickshell QML.

---

## 5. Platform Differences: Omarchy vs. CachyOS (KDE Plasma 6)

| Feature | Omarchy Apple Silicon | CachyOS Intel / PC (Target) |
|---|---|---|
| **OS & Shell** | Omarchy (Hyprland / Quickshell) | CachyOS (KDE Plasma 6 / Wayland) |
| **Wi-Fi Hardware** | Apple Broadcom PCIe (`brcmfmac`) | Intel Wi-Fi 6E AX211 (`iwlwifi`) |
| **AWDL Driver** | Firmware-native AWDL via DKMS | Userspace AWDL via `omdrop-owl` |
| **Channel Handling** | Hardware handles multi-channel hopping | Shares AP / Hotspot channel (6, 44, 149) |
| **Notifications** | `omarchy-notification-send` | `notify-send` / Freedesktop Notifications |
| **File Picker** | Nautilus / Omarchy custom | `kdialog` / XDG Desktop Portal (KDE) |
| **Terminal Launch** | `omarchy-launch-floating-terminal...` | `konsole -e` / `xdg-terminal-exec` |
| **Browser Launch** | `omarchy-launch-browser` | `xdg-open` |
| **Taskbar UI** | Quickshell widget (`manifest.json`) | Native KDE Plasma 6 Applet (Plasmoid) |

---

## 6. Hardware Implementation: Intel AX211 (`iwlwifi`) Exclusive Mode

### The Breakthrough: Ad-hoc (IBSS) Cell on Channel 6
Originally, Intel cards failed in monitor mode because Intel firmware suppresses 802.11 ACKs for unicast frames in sniffer context. Upstream `omdrop-owl` solved this limitation without requiring custom firmware through **Exclusive Mode**:

1. **How It Works**:
   - Because AWDL frames are 802.11 IBSS frames with a fixed BSSID (`00:25:00:ff:94:73`), `omdrop-discoverable` turns the station interface (`wlan0`) into an HT20 ad-hoc (IBSS) cell on Channel 6 (2437 MHz) joined to that exact BSSID.
   - This provides the Intel firmware with an active address and BSSID match, enabling hardware **802.11 ACK transmission for unicast frames from the iPhone**.
   - An accompanying monitor interface (`mon0`) handles packet injection with `-F` (fixed radio), `-E` (metric election), and `-S pin` (channel pinning).
2. **Reliability Patch (`owl-07-intel-reliability.patch`)**:
   - Retries unicast frames on `EAGAIN` from non-blocking pcap handles instead of dropping them, eliminating TCP ACK loss during high-throughput transfers.
   - Refreshes peer expiration on data frames and sets peer timeout to 5s, preventing active iPhones from being dropped mid-transfer.
3. **UX & Network Lifecycle**:
   - While receiving is **ON**, Wi-Fi temporarily pauses because the single physical radio is dedicated to the Channel 6 AirDrop cell.
   - While receiving is **OFF** (or after the window expires), `omdrop-discoverable` automatically converts the interface back to managed mode and NetworkManager reconnects to the previous Wi-Fi network.
   - No router channel changes or external USB adapters are required.

---

## 7. KDE Plasma 6 Taskbar Widget Architecture

A native KDE Plasma 6 Plasmoid (`cachyos-airdrop`) is installed into `~/.local/share/plasma/plasmoids/org.cachyos.airdrop/`:

```
org.cachyos.airdrop/
├── metadata.json                         # Plasma 6 Applet metadata
└── contents/
    ├── ui/
    │   ├── main.qml                      # PlasmoidItem root & state controller
    │   ├── CompactRepresentation.qml     # Taskbar / Panel icon with badges
    │   ├── FullRepresentation.qml        # Expanded AirDrop control panel
    │   └── Radar.qml                     # Ported QtQuick radar visualization
    └── resources/
        └── icons/                        # AirDrop SVG icons
```

### Key Integrations:
- **`CompactRepresentation.qml`**: Placed directly on the KDE taskbar/panel (or system tray). Displays the AirDrop symbol, status color, active countdown timer badge, and click actions.
- **`FullRepresentation.qml`**: Native KDE styling using `org.kde.kirigami` and `org.kde.plasma.components 3.0`. Contains receive toggle, time duration slider, device name, download folder chooser (`kdialog`), and the interactive radar.
- **Backend IPC**: Calls the `omdrop` CLI (`status --json`, `on`, `off`, `send`, `peers`) asynchronously using `Plasma5Support.DataSource` (executable dataengine) or a lightweight Python/D-Bus bridge.
