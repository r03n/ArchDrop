#!/usr/bin/env bash
# archdrop-test.sh -- Automated offline test & telemetry logger for ArchDrop
# Usage: ./archdrop-test.sh [DURATION_SECONDS]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURATION="${1:-60}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TEST_DIR="$SCRIPT_DIR/test-logs/session-$TIMESTAMP"
mkdir -p "$TEST_DIR"

PREV_WIFI=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="wifi" || $2=="802-11-wireless"{print $1; exit}')
HOTSPOT_CON="ArchDrop-Hotspot"
LOGGER_PID=""

echo "=========================================================="
echo "           ArchDrop Offline Hotspot Test Tool             "
echo "=========================================================="
echo "Session:        $TIMESTAMP"
echo "Duration:       ${DURATION} seconds"
echo "Previous Wi-Fi: ${PREV_WIFI:-<none>}"
echo "Target Channel: Channel 6 (2437 MHz)"
echo "Log Directory:  $TEST_DIR"
echo "=========================================================="

cleanup() {
    echo ""
    echo "[*] Cleaning up test session and restoring network..."
    
    # 1. Kill background logger
    if [[ -n "$LOGGER_PID" ]] && kill -0 "$LOGGER_PID" 2>/dev/null; then
        kill "$LOGGER_PID" 2>/dev/null || true
    fi

    # 2. Stop ArchDrop receiver and radio
    echo "[*] Stopping ArchDrop receiver..."
    "$SCRIPT_DIR/omdrop-plugin/bin/omdrop" off --force >/dev/null 2>&1 || true

    # 3. Stop ArchDrop-Hotspot
    echo "[*] Stopping ArchDrop hotspot..."
    nmcli connection down "$HOTSPOT_CON" >/dev/null 2>&1 || true

    # 4. Reconnect to previous Wi-Fi
    if [[ -n "$PREV_WIFI" && "$PREV_WIFI" != "$HOTSPOT_CON" ]]; then
        echo "[*] Reconnecting to Wi-Fi ($PREV_WIFI)..."
        nmcli connection up "$PREV_WIFI" >/dev/null 2>&1 || true
        for _ in $(seq 10); do
            if ip route show default 2>/dev/null | grep -q default; then
                echo "[+] Internet connection restored."
                break
            fi
            sleep 1
        done
    fi

    # 5. Compile consolidated diagnostic report
    compile_report

    echo "=========================================================="
    echo "[+] Test complete! Report generated at:"
    echo "    $TEST_DIR/REPORT.md"
    echo "=========================================================="
    exit 0
}

trap cleanup EXIT INT TERM

# Ensure Hotspot connection profile exists
if ! nmcli connection show "$HOTSPOT_CON" >/dev/null 2>&1; then
    echo "[*] Creating $HOTSPOT_CON NetworkManager connection..."
    nmcli connection add type wifi ifname wlan0 con-name "$HOTSPOT_CON" autoconnect no \
        ssid "ArchDrop" mode ap 802-11-wireless.band bg 802-11-wireless.channel 6 \
        ipv4.method shared ipv6.method shared >/dev/null 2>&1
fi

# Step 1: Activate Hotspot
echo "[*] Activating ArchDrop Hotspot on Channel 6..."
nmcli connection up "$HOTSPOT_CON" > "$TEST_DIR/hotspot_up.log" 2>&1 || {
    echo "[-] Failed to activate $HOTSPOT_CON. Check $TEST_DIR/hotspot_up.log"
    exit 1
}

# Step 2: Start ArchDrop receiver
echo "[*] Starting ArchDrop receiver (duration: $(( DURATION + 30 ))s)..."
"$SCRIPT_DIR/omdrop-plugin/bin/omdrop" on "$(( DURATION + 30 ))s" > "$TEST_DIR/omdrop_on.log" 2>&1 || {
    echo "[-] Warning: omdrop on reported an error. Continuing to capture diagnostics..."
}

# Step 3: Start BLE Continuity presence advertisement
if [ -x "/usr/lib/omdrop/ble-airdrop-adv.py" ] && bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
    echo "[*] Broadcasting BLE Continuity AirDrop presence advert..."
    python3 /usr/lib/omdrop/ble-airdrop-adv.py --arm A --seconds "$DURATION" --interval-ms 100 > "$TEST_DIR/ble.log" 2>&1 &
fi

# Step 4: Record Initial State
{
    echo "=== Network Interfaces ==="
    iw dev
    echo ""
    echo "=== wlan0 Info ==="
    iw dev wlan0 info 2>&1
    echo ""
    echo "=== awdl0 Address ==="
    ip -6 addr show dev awdl0 2>&1 || true
    echo ""
    echo "=== mon0 Status ==="
    ip link show mon0 2>&1 || true
    echo ""
    echo "=== Listening Sockets ==="
    ss -tlpn 2>&1 | grep 8771 || true
} > "$TEST_DIR/initial_state.txt"

# Step 5: Start background telemetry loop
(
    while true; do
        TS=$(date +%H:%M:%S)
        {
            echo "--- Telemetry Snapshot at $TS ---"
            
            # Check receiver status
            RECV_ACTIVE=$(systemctl --user is-active airdrop-receiver.service 2>/dev/null || echo "inactive")
            echo "Receiver Active: $RECV_ACTIVE"

            # Check open connections on 8771
            CONNS=$(ss -t -a 'sport = :8771 or dport = :8771' 2>/dev/null || true)
            if [[ -n "$CONNS" ]]; then
                echo "Connections on 8771:"
                echo "$CONNS"
            fi

            # Check OWL peer events
            if [[ -r /run/omdrop-owl/owl.log ]]; then
                PEERS_SEEN=$(grep -oE '(add|remove) peer [0-9a-f:]+' /run/omdrop-owl/owl.log 2>/dev/null | tail -n 5 || true)
                if [[ -n "$PEERS_SEEN" ]]; then
                    echo "Recent OWL Peer Events:"
                    echo "$PEERS_SEEN"
                fi
            fi

            # Check connected Wi-Fi clients on the hotspot
            STATIONS=$(iw dev wlan0 station dump 2>/dev/null | awk '/^Station/{print $2}' || true)
            if [[ -n "$STATIONS" ]]; then
                echo "Connected Wi-Fi Clients: $STATIONS"
            fi

            echo ""
        } >> "$TEST_DIR/telemetry.log"
        sleep 2
    done
) &
LOGGER_PID=$!

echo ""
echo "=========================================================="
echo "[+] ArchDrop Hotspot is now ACTIVE on Channel 6!"
echo ""
echo "👉 CRITICAL STEP 1: Connect your iPhone to ArchDrop Wi-Fi:"
echo "   - On your iPhone, open Settings > Wi-Fi"
echo "   - Tap and connect to 'ArchDrop' (open Wi-Fi hotspot)"
echo ""
echo "👉 STEP 2: AirDrop Transfer:"
echo "   - Ensure Settings > General > AirDrop is set to 'Everyone for 10 Minutes'"
echo "   - Open Photos, select any photo, tap Share > AirDrop"
echo "   - Look for 'Zenux' in the AirDrop targets and tap it!"
echo "=========================================================="
echo ""

# Step 6: Interactive Countdown Loop
REMAINING="$DURATION"
while (( REMAINING > 0 )); do
    printf "\r[*] Testing... [ %2ds remaining ] (Press Enter to finish early) " "$REMAINING"
    read -r -t 1 && break || true
    (( REMAINING-- ))
done
printf "\n"

compile_report() {
    local REPORT="$TEST_DIR/REPORT.md"
    local LATEST="$SCRIPT_DIR/test-logs/LATEST.md"
    
    # Collect journal entries for airdrop-receiver during this test
    journalctl --user -u airdrop-receiver.service --since "-$(( DURATION + 60 ))s" --no-pager > "$TEST_DIR/journal_receiver.log" 2>&1 || true

    # Collect OWL logs
    cp -f /run/omdrop-owl/owl.log "$TEST_DIR/owl_final.log" 2>/dev/null || true
    cp -f /run/omdrop-owl/announce.log "$TEST_DIR/announce_final.log" 2>/dev/null || true

    local DISCOVER_REQS
    DISCOVER_REQS=$(grep -c "POST /Discover" "$TEST_DIR/journal_receiver.log" 2>/dev/null || echo 0)

    local ASK_REQS
    ASK_REQS=$(grep -c "POST /Ask" "$TEST_DIR/journal_receiver.log" 2>/dev/null || echo 0)

    local PEERS_COUNT
    PEERS_COUNT=$(grep -oE 'add peer [0-9a-f:]+' "$TEST_DIR/owl_final.log" 2>/dev/null | sort -u | wc -l || echo 0)

    cat <<EOF > "$REPORT"
# ArchDrop Offline Test Report

- **Date / Time**: $(date)
- **Session ID**: \`$TIMESTAMP\`
- **Test Duration**: ${DURATION}s
- **Wi-Fi Interface**: \`wlan0\` on Channel 6 (2437 MHz, type AP)
- **Previous Wi-Fi Restored**: \`${PREV_WIFI:-none}\`

---

## 1. Summary of Results

| Metric | Result | Status |
|---|---|---|
| **Hotspot Active** | Yes (Channel 6) | PASS |
| **AWDL Link-Local Interface** | $(grep -q "inet6 fe80" "$TEST_DIR/initial_state.txt" && echo "fe80::... present" || echo "Missing") | $(grep -q "inet6 fe80" "$TEST_DIR/initial_state.txt" && echo "PASS" || echo "FAIL") |
| **Port 8771 Receiver** | $(grep -q "8771" "$TEST_DIR/initial_state.txt" && echo "Listening" || echo "Inactive") | $(grep -q "8771" "$TEST_DIR/initial_state.txt" && echo "PASS" || echo "FAIL") |
| **AWDL Peers Detected** | **$PEERS_COUNT peer(s)** | $( (( PEERS_COUNT > 0 )) && echo "FOUND" || echo "NONE" ) |
| **HTTPS /Discover Requests** | **$DISCOVER_REQS request(s)** | $( (( DISCOVER_REQS > 0 )) && echo "RECEIVED" || echo "NONE" ) |
| **HTTPS /Ask Transfer Requests**| **$ASK_REQS request(s)** | $( (( ASK_REQS > 0 )) && echo "RECEIVED" || echo "NONE" ) |

---

## 2. Key Observations

EOF

    if (( DISCOVER_REQS > 0 )); then
        echo "- **Success**: Apple devices probed Zenux over HTTPS (\`/Discover\`)!" >> "$REPORT"
    else
        echo "- **Notice**: No incoming \`/Discover\` probes were received during this ${DURATION}s window." >> "$REPORT"
        echo "  - Make sure the iPhone has AirDrop set to **'Everyone for 10 Minutes'**." >> "$REPORT"
        echo "  - Wake the iPhone screen and keep the AirDrop Share Sheet open." >> "$REPORT"
    fi

    if (( PEERS_COUNT > 0 )); then
        echo "- **AWDL Radio**: OWL detected $PEERS_COUNT distinct Apple MAC address(es) on Channel 6." >> "$REPORT"
    else
        echo "- **AWDL Radio**: No AWDL frame exchanges were picked up by OWL on Channel 6." >> "$REPORT"
    fi

    cat <<EOF >> "$REPORT"

---

## 3. Logs & Artifacts

- **Initial State**: [\`initial_state.txt\`](file://$TEST_DIR/initial_state.txt)
- **Receiver Journal Log**: [\`journal_receiver.log\`](file://$TEST_DIR/journal_receiver.log)
- **OWL Daemon Log**: [\`owl_final.log\`](file://$TEST_DIR/owl_final.log)
- **mDNS Announce Log**: [\`announce_final.log\`](file://$TEST_DIR/announce_final.log)
- **Telemetry Timeline**: [\`telemetry.log\`](file://$TEST_DIR/telemetry.log)
EOF

    ln -sfn "$REPORT" "$LATEST"
}
