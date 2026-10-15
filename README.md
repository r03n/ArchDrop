# ArchDrop: Apple AirDrop for CachyOS / Arch Linux (KDE Plasma 6)

Native Apple AirDrop implementation for Linux, specifically tailored for **CachyOS** (and Arch Linux) running **KDE Plasma 6** on standard PC hardware (including **Intel Wi-Fi 6E AX211** `iwlwifi` and MediaTek chipsets).

---

## ✨ Features

- **Native KDE Plasma 6 Applet (Plasmoid)**:
  - System Tray icon with live status, active countdown timer badge, and radar visualizer.
  - Interactive transfer controls (10 min, 30 min, 1 hour, or 1 file receive windows).
  - Configurable download folder with native KDE folder picker (`kdialog`).
- **Interactive Transfer Prompt**:
  - Modal prompt (`kdialog` / `notify-send`) showing sender device name, file list, total transfer size, and thumbnail preview.
  - User can Accept or Decline incoming transfers.
- **Intel AX211 Exclusive Mode**:
  - Solves Intel Wi-Fi firmware unicast 802.11 ACK limitations via an ad-hoc (IBSS) cell on Channel 6 (`00:25:00:ff:94:73`).
  - Automatic Wi-Fi reconnection when the AirDrop receiving window finishes.
  - Zero router channel lock or custom firmware required.
- **PatientReader Transfer Robustness**:
  - Seamlessly handles iOS chunk boundary uploads without connection reset or timeout stalls.
  - Socket-level `TCP_NODELAY` optimizations for low latency.

---

## 📁 Repository Structure

```
.
├── install-archdrop.sh                 # One-step automated installer
├── archdrop-test.sh                    # Diagnostic and verification test suite
├── AGENTS.md                           # Architecture and development guide
├── intel_monitor_mode_ack_analysis.md  # Technical hardware ACK analysis
├── plasmoids/
│   └── org.cachyos.archdrop/           # KDE Plasma 6 Plasmoid source
├── omdrop-plugin/                      # User-space AirDrop daemon & omdrop CLI
└── omdrop-owl/                         # Userspace AWDL daemon & radio controller
```

---

## 🚀 Quickstart Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/r03n/ArchDrop.git
   cd ArchDrop
   ```

2. **Run the automated installer**:
   ```bash
   ./install-archdrop.sh
   ```

The installer will:
- Install all required dependencies via `pacman`.
- Build the patched OWL userspace daemon with Intel AX211 reliability patches.
- Stage and install radio tools to `/usr/lib/omdrop`.
- Configure Polkit (`io.github.t4t5.omdrop-owl.policy`) and NetworkManager unmanaged rules.
- Set up the systemd user service (`airdrop-receiver.service`).
- Install and register the ArchDrop Plasmoid into KDE Plasma 6.

---

## 🛠️ CLI Usage

ArchDrop can be operated either through the KDE System Tray widget or via the `omdrop` CLI:

```bash
# Start a 10-minute receive window
omdrop on 10m

# Check receiving status
omdrop status

# List nearby Apple devices
omdrop peers

# Send files or web links to a nearby Apple device
omdrop send ~/photo.jpg
omdrop send "iPhone" https://cachyos.org/

# Stop receiving and restore normal Wi-Fi connection
omdrop off

# Verify system readiness and configuration
omdrop doctor
```

---

## 📜 License

Licensed under GPLv3. Based on [omdrop](https://github.com/brentkearney/omdrop-plugin) and [OWL](https://github.com/jedbillyb/owl).
