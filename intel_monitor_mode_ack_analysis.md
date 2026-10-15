# Technical Analysis: Intel 802.11 Monitor Mode ACK Omission & Workaround Research

**Document Purpose**: This document provides a comprehensive technical breakdown of why Intel wireless adapters (driven by `iwlwifi`) do not transmit 802.11 ACK frames for unicast frames addressed to their own MAC in monitor mode. It details the underlying protocol constraints, kernel architecture, driver/firmware behavior, empirical evidence, and specific technical vectors for researching potential workarounds.

---

## 1. Problem Statement & Protocol Constraints

### 1.1 The Observed Phenomenon
When an Intel wireless card (e.g., Intel Wireless-AC 3160/7265/8265/9260, Wi-Fi 6/6E AX200/AX201/AX210, Wi-Fi 7 BE200) is placed into pure monitor mode (`NL80211_IFTYPE_MONITOR`), it operates purely as a passive RF observer. If a remote station or Access Point transmits a valid unicast 802.11 frame whose Receiver Address (RA / Address 1) matches the Intel card's hardware (or locally configured) MAC address, **the Intel adapter never generates an 802.11 Acknowledgment (ACK) frame**.

### 1.2 The Hard Real-Time Constraint: SIFS
Under the IEEE 802.11 standard, link-layer acknowledgments must be transmitted precisely after the **Short Interframe Space (SIFS)**:
* **802.11b**: 10 µs
* **802.11a / 802.11g (OFDM) / 802.11n / 802.11ac / 802.11ax (5 GHz / 6 GHz)**: 16 µs
* **802.11n / 802.11ac / 802.11ax (2.4 GHz)**: 10 µs

#### Why Software/Userspace Cannot Inject ACKs:
Host operating system scheduling, user-kernel context switching, PCIe DMA transfers, and driver ring buffer latencies generally require between **100 µs and several milliseconds**. Because 10–16 µs is well below the latency of any host software stack, **802.11 ACK frames must be generated entirely by MAC hardware or on-chip firmware microcode**.

If the hardware/firmware does not automatically emit the ACK frame:
1. The remote sender observes an ACK timeout.
2. The sender retransmits the frame (up to `dot11ShortRetryLimit` / `dot11LongRetryLimit`, usually 7 times).
3. The sender terminates the connection or handshake (e.g., `hostapd` immediately deauthenticates a client if the Association Response is unacknowledged).

---

## 2. Linux Wireless Subsystem (`cfg80211` / `mac80211` / `nl80211`)

### 2.1 The Active Monitor Mode Standard
The Linux kernel provides an explicit configuration for monitor interfaces that need to acknowledge incoming unicast frames: **Active Monitor Mode**.

#### UAPI Definition (`include/uapi/linux/nl80211.h`):
```c
/**
 * enum nl80211_mntr_flags - monitor configuration flags
 * ...
 * @NL80211_MNTR_FLAG_ACTIVE: use the configured MAC address
 *    and ACK incoming unicast packets.
 */
enum nl80211_mntr_flags {
    ...
    NL80211_MNTR_FLAG_ACTIVE,
    ...
};
```

#### Driver Capability Advertisement:
```c
/**
 * enum nl80211_feature_flags - device/driver features
 * ...
 * @NL80211_FEATURE_ACTIVE_MONITOR: This driver supports an active monitor
 *    interface. An active monitor interface behaves like a normal monitor
 *    interface, but gets added to the driver. It ensures that incoming
 *    unicast packets directed at the configured interface address get ACKed.
 */
enum nl80211_feature_flags {
    ...
    NL80211_FEATURE_ACTIVE_MONITOR = 1 << 17,
    ...
};
```

### 2.2 Kernel Enforcement (`net/wireless/nl80211.c`)
When a user attempts to activate active monitor mode using:
```bash
sudo iw dev <intf> set monitor active
```
The kernel processes the request in `nl80211_parse_mon_options()`:
```c
if (flags & BIT(NL80211_MNTR_FLAG_ACTIVE)) {
    if (!wiphy_ext_feature_isset(&rdev->wiphy, NL80211_FEATURE_ACTIVE_MONITOR))
        return -EOPNOTSUPP;
}
```

### 2.3 Upstream Linux Kernel Driver Audit
Across the entire upstream Linux wireless stack, **only MediaTek drivers (`mt76` and `mt7601u`) implement and advertise `NL80211_FEATURE_ACTIVE_MONITOR`**.
* In `mt76`, the driver configures hardware RX filtering to recognize its own MAC and triggers hardware ACK transmission while leaving monitor capture active.
* In **`iwlwifi`**, this feature flag is **never set**. Any attempt to configure active monitor mode returns `-EOPNOTSUPP` ("Operation not supported").

---

## 3. Intel `iwlwifi` Driver & Firmware Architecture

### 3.1 Architecture Overview
Intel Wi-Fi support is divided into three components:
1. **PCIe Bus Transport** (`drivers/net/wireless/intel/iwlwifi/pcie/`).
2. **Mac80211 Driver Layer**:
   * `iwlmvm`: Modern devices (Family 7000, 8000, 9000, AX200/AX210, BE200).
   * `iwldvm`: Legacy devices (5000, 6000 series).
3. **Closed-Source Firmware Microcode** (`iwlwifi-*.ucode`):
   * Runs on internal Tensilica Xtensa or ARC RISC cores on the Wi-Fi silicon.
   * Handles low-level RF synthesis, CSMA/CA backoff, SIFS timing, MAC filtering, and ACK synthesis.

### 3.2 Firmware Monitor Mode Context
In `iwlmvm/mac80211.c` and `iwlmvm/mvm.h`:
* When an interface of type `NL80211_IFTYPE_MONITOR` is started, `iwlmvm` configures an RX filter via internal host commands (such as `MAC_CONTEXT_CMD` / `PHY_CONTEXT_CMD` / `RX_FILTER_CMD`).
* The driver sets `mvmvif->monitor_active = true` and enables promiscuous receive (`IWL_RXON_FILTER_PROMISC`).
* Crucially, **the firmware does not register a station or BSS context for the monitor interface**. In Intel microcode, the automatic ACK generation engine is tied strictly to an active, bound station/AP BSS ID. Because pure monitor mode creates no BSS binding in the firmware table, the microcode treats all incoming frames as third-party traffic and suppresses hardware ACK transmission.

---

## 4. Empirical Evidence & Academic Literature

### 4.1 WiSec 2023 Research Paper
* **Reference**: Vanhoef, M., Jiao, X., Liu, W., & Moerman, I. (2023). *Testing and Improving the Correctness of Wi-Fi Frame Injection*. In *Proceedings of the 16th ACM Conference on Security and Privacy in Wireless and Mobile Networks (WiSec '23)*.
* **Findings (Section 3.2, "Acknowledgements and retransmissions")**:
  > *"Whether an interface in monitor mode acknowledges received frames also depends on various factors. In theory, when in pure monitor mode, acknowledgements should only be sent if the active flag was set... An inspection of the Linux kernel source code indicates that only two out of more than 60 Wi-Fi drivers support this flag: the MediaTek mt76 and mt7601u driver.*
  >
  > *Interestingly, we found that the WN-722N acknowledges received frames in pure monitor mode without setting the active flag."*

* **Comparative Behavior**:
  * **Atheros AR9271 (`ath9k_htc`)**: Has a known firmware behavior/bug where the MAC address filter and ACK generator remain active for unicast frames directed to its hardware address, even in pure monitor mode.
  * **MediaTek MT7612U (`mt76`)**: Explicitly supports `NL80211_FEATURE_ACTIVE_MONITOR` via driver and hardware registers.
  * **Intel Wireless-AC 3160 (`iwlwifi`)**: Strictly silent. Never sends ACKs in pure monitor mode.

### 4.2 Security Research Tooling Failures
* **Open Wireless Link ([`seemoo-lab/owl`](https://github.com/seemoo-lab/owl))**:
  When attempting to implement Apple's AWDL (AirDrop) in userspace over monitor mode, Intel cards fail because incoming unicast frames from the iPhone/Mac are not ACKed by the Intel card. The peer exhausts retries and aborts the connection.
* **[`hcxdumptool`](https://github.com/ZerBea/hcxdumptool)**:
  Author ZerBea explicitly lists Intel adapters as "Not recommended" because the hardware cannot handle active monitor mode interactions and link-layer ACK handshakes in monitor mode.

---

## 5. Known Workarounds & Their Drawbacks

### 5.1 Workaround 1: Mixed Monitor Mode (Dual Virtual Interfaces)
On modern Linux kernels, a single physical Intel NIC (`phy0`) can run multiple virtual interfaces simultaneously:
1. **Primary Interface** (`wlan0`): Configured as an AP or Client interface.
2. **Secondary Interface** (`wlan0mon`): Configured as a Monitor interface.

#### Implementation (Dummy AP):
```bash
# 1. Bring down primary interface
sudo ip link set wlan0 down

# 2. Add virtual monitor interface
sudo iw dev wlan0 interface add wlan0mon type monitor

# 3. Set primary interface to AP mode and configure dummy AP
sudo iw dev wlan0 set type __ap
sudo ip link set wlan0 up
sudo iw dev wlan0 ap start "dummy-net" 2412 100 1 head 80000000000000000000c4e984dbfb7bc4e984dbfb7b0000000000000000000064000000

# 4. Bring up monitor interface
sudo ip link set wlan0mon up
```

#### Drawbacks & Failure Modes of Mixed Mode:
1. **Channel Locking**: The monitor interface is forced to stay on whatever channel the AP/Client interface is operating on. Channel hopping disrupts the virtual AP.
2. **Unwanted RF Emissions**: The AP interface transmits beacons and responds to probe requests unless custom low-level driver modifications suppress them.
3. **Firmware Frame Drops**: As documented by Vanhoef et al., when injecting frames on `wlan0mon`, if the source address differs from the AP interface MAC, `iwlwifi` firmware may silently drop or corrupt the injected frame.

### 5.2 Workaround 2: Dedicated Dual-NIC Architecture
Use the Intel card strictly for high-throughput reception / analysis, and a secondary USB dongle with open firmware (e.g., Atheros AR9271 / `ath9k_htc` or MediaTek MT7612U / `mt76`) for packet injection and link-layer interaction.

---

## 6. Vectors for AI-Assisted Workaround Research

If developing a novel workaround or researching new driver/firmware modifications, investigate the following technical vectors:

### Vector A: "Stealth" Station / AP Firmware Context in `iwlmvm`
* **Hypothesis**: The Intel firmware does not require active beacons to generate ACKs; it only requires an active **Station / BSS Context Table Entry** matching the target MAC.
* **Investigation Target**:
  * In `drivers/net/wireless/intel/iwlwifi/mvm/mac-ctxt.c` and `binding.c`, examine `iwl_mvm_mac_ctxt_cmd()` and `iwl_mvm_add_sta()`.
  * Can `iwlmvm` be patched to send an internal `ADD_STA` or `BINDING_CMD` to firmware when initializing a monitor interface, convincing the firmware to keep an ACK-generating MAC entry in its hardware filter table without actually connecting to an AP or emitting beacon frames?

### Vector B: Modifying `iwlwifi` Driver RX Filter Flags
* **Hypothesis**: Intel firmware supports custom filtering bits via `PHY_CONTEXT_CMD` and `MAC_CFG_FILTER_*`.
* **Investigation Target**:
  * Inspect the definition of `MAC_CFG_FILTER_*` flags in `drivers/net/wireless/intel/iwlwifi/fw/api/mac.h`.
  * Is there a bitmask flag (or diagnostic testmode flag) in the firmware API that decouples unicast ACK generation from the BSS association state?

### Vector C: Intel Testmode / Debug Command Interface
* **Hypothesis**: Intel's diagnostic tools (and the kernel `iwl_testmode` interface in `drivers/net/wireless/intel/iwlwifi/mvm/testmode.c`) allow issuing raw host commands directly to the firmware.
* **Investigation Target**:
  * Can `NL80211_CMD_TESTMODE` send raw commands to configure the transceiver in a calibration or loopback mode that acknowledges all packets directed to a specific MAC register?

### Vector D: Firmware Microcode Reverse Engineering
* **Hypothesis**: Intel `.ucode` files are segmented TLV structures containing code sections for the internal Tensilica Xtensa / ARC cores.
* **Investigation Target**:
  * Look at open-source firmware extraction tools (e.g., `iwlwifi-firmware` reverse engineering research).
  * Can the RX interrupt handler in the microcode be patched to bypass the check that disables the TX ACK trigger when `FILTER_PROMISC` is set?

---

## 7. Key References & Source Links
* **Kernel UAPI**: [`include/uapi/linux/nl80211.h`](file:///usr/include/linux/nl80211.h#L5122-L5123)
* **Kernel Feature Enum**: [`include/uapi/linux/nl80211.h`](file:///usr/include/linux/nl80211.h#L6782)
* **Kernel Monitor Check**: `net/wireless/nl80211.c` (`nl80211_parse_mon_options`)
* **Driver Source**: `drivers/net/wireless/intel/iwlwifi/`
* **WiSec 2023 Paper**: [Vanhoef et al., "Testing and Improving the Correctness of Wi-Fi Frame Injection"](https://papers.mathyvanhoef.com/wisec2023-wifi-injection.pdf)
* **Testing Repository**: [`vanhoefm/wifi-injection`](https://github.com/vanhoefm/wifi-injection)
