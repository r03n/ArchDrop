#!/usr/bin/env bash
# install-archdrop.sh -- Automated installer for ArchDrop on CachyOS / Arch Linux (KDE Plasma 6)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWL_DIR="$SCRIPT_DIR/omdrop-owl"
PLUGIN_DIR="$SCRIPT_DIR/omdrop-plugin"
PLASMOID_DIR="$SCRIPT_DIR/plasmoids/org.cachyos.archdrop"

echo "=========================================================="
echo "           ArchDrop Installer for CachyOS / KDE           "
echo "=========================================================="

# 1. Check required pacman packages
MISSING_PKGS=()
for pkg in python-libarchive-c python-zeroconf python-ifaddr keyutils iw libev libpcap libnl kdialog libnotify wl-clipboard; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if (( ${#MISSING_PKGS[@]} > 0 )); then
    echo "[-] Missing required packages: ${MISSING_PKGS[*]}"
    echo "[*] Installing dependencies with pacman (sudo required)..."
    sudo pacman -S --needed "${MISSING_PKGS[@]}"
else
    echo "[+] All required system packages are installed."
fi

# 2. Build and Stage omdrop-owl
echo "[*] Building OWL daemon with Intel reliability patches..."
bash "$OWL_DIR/tools/build-owl.sh"
echo "[*] Staging radio backend tools..."
bash "$OWL_DIR/tools/stage.sh"

# 3. Install to /usr/lib/omdrop and configure system policies
echo "[*] Installing radio backend to /usr/lib/omdrop (sudo required)..."
sudo pkill -f "[o]wl -i" 2>/dev/null || true
sudo mkdir -p /usr/lib/omdrop
sudo cp -r "$OWL_DIR/build/lib/." /usr/lib/omdrop/
sudo chmod 755 /usr/lib/omdrop/omdrop-discoverable /usr/lib/omdrop/owl /usr/lib/omdrop/send-to-peer /usr/lib/omdrop/*.py
sudo chmod 644 /usr/lib/omdrop/owl-profiles

# Polkit policy
echo "[*] Installing Polkit policy for passwordless active-session discovery..."
sudo cp -f "$OWL_DIR/packaging/omdrop-owl.policy" /usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy
sudo chmod 644 /usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy

# NetworkManager unmanaged rule
echo "[*] Installing NetworkManager rule for awdl0 and mon0..."
sudo mkdir -p /usr/lib/NetworkManager/conf.d
sudo cp -f "$OWL_DIR/packaging/99-omdrop-owl-unmanaged.conf" /usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf
sudo chmod 644 /usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf
sudo systemctl reload NetworkManager 2>/dev/null || true

# Allow untested if needed (iwlwifi is tested, but enable flag for safety)
sudo mkdir -p /etc/omdrop
echo 1 | sudo tee /etc/omdrop/allow-untested >/dev/null

# 4. Set up user CLI and service
echo "[*] Setting up ArchDrop CLI and user service..."
mkdir -p "$HOME/.local/bin"
ln -sfn "$PLUGIN_DIR/bin/omdrop" "$HOME/.local/bin/omdrop"
"$PLUGIN_DIR/bin/omdrop" setup || true

# 5. Install / Update KDE Plasma 6 Plasmoid
echo "[*] Installing ArchDrop System Tray Plasmoid..."
if kpackagetool6 --type Plasma/Applet --show org.cachyos.archdrop >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID_DIR"
else
    kpackagetool6 --type Plasma/Applet --install "$PLASMOID_DIR"
fi

# 6. Add ArchDrop to Plasma System Tray config if kwriteconfig6 exists
if command -v kwriteconfig6 >/dev/null 2>&1; then
    echo "[*] Registering ArchDrop in KDE System Tray..."
    TRAY_CONF="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "$TRAY_CONF" ]]; then
        # Check current extraItems
        EXTRAS=$(kreadconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 46 --group Applets --group 51 --group General --key extraItems 2>/dev/null || true)
        if [[ "$EXTRAS" != *"org.cachyos.archdrop"* && -n "$EXTRAS" ]]; then
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 46 --group Applets --group 51 --group General --key extraItems "$EXTRAS,org.cachyos.archdrop"
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 46 --group Applets --group 51 --group General --key knownItems "$EXTRAS,org.cachyos.archdrop"
        fi
    fi
fi

echo ""
echo "=========================================================="
echo "[+] ArchDrop installation complete!"
echo "    - CLI: 'omdrop' is available in ~/.local/bin/omdrop"
echo "    - Radio backend: /usr/lib/omdrop"
echo "    - System Tray: ArchDrop applet installed in KDE Plasma"
echo ""
echo "Tip: Intel AX211 runs in Exclusive Mode on Channel 6."
echo "     When receiving, Wi-Fi switches to the AirDrop cell,"
echo "     and automatically reconnects when receiving stops."
echo "     Run 'omdrop doctor' to verify readiness."
echo "=========================================================="
