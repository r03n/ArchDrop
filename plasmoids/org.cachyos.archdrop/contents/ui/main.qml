pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Plasmoid Properties
    Plasmoid.icon: "network-wireless-symbolic"
    Plasmoid.title: i18n("ArchDrop")
    toolTipMainText: i18n("ArchDrop")
    toolTipSubText: {
        if (hardwareIssue !== "") return hardwareIssue;
        if (channelIssue !== "" && !receiving) return channelIssue;
        if (receiving) {
            if (remaining > 0) return i18n("Visible (%1m remaining - Exclusive Mode)", Math.ceil(remaining / 60));
            return i18n("Visible (Exclusive Mode)");
        }
        return i18n("Ready to Receive (Exclusive Mode)");
    }

    // Active status places icon in system tray main row when receiving, passive otherwise
    Plasmoid.status: (receiving || visibility === 1) ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    // State
    property bool receiving: false
    property int visibility: -1 // -1 unknown, 0 no, 1 yes
    property int remaining: -1
    property string deviceName: ""
    property string downloadDir: ""
    property string audience: "everyone"
    property int senders: 0
    property string channelIssue: ""
    property string hardwareIssue: ""
    property bool busy: false
    property bool soundMuted: false
    property bool peerScanBusy: false
    property var peers: []

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
    }

    // Executable DataSource for running CLI commands
    Plasma5Support.DataSource {
        id: execEngine
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            var exitCode = data["exit code"];
            disconnectSource(sourceName);
            handleResult(sourceName, stdout, stderr, exitCode);
        }

        function exec(cmd) {
            connectSource(cmd);
        }
    }

    // Periodic status polling timer
    Timer {
        id: statusTimer
        interval: (root.expanded || root.receiving) ? 2500 : 8000
        repeat: true
        running: true
        onTriggered: {
            root.refreshStatus();
            if (root.expanded && root.receiving) {
                root.refreshPeers();
            }
        }
    }

    // Doctor probe timer to check Wi-Fi channel compatibility
    Timer {
        id: doctorTimer
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.checkDoctor()
    }

    function runCmd(subcommand, tag) {
        var cmd = "bash -c 'export PATH=\"$HOME/.local/bin:/usr/lib/omdrop:/usr/bin:/usr/local/bin:$PATH\"; " +
                  "if command -v omdrop >/dev/null 2>&1; then omdrop " + subcommand + "; " +
                  "elif [ -x /usr/lib/omdrop/omdrop ]; then /usr/lib/omdrop/omdrop " + subcommand + "; " +
                  "else echo \"omdrop command not found\" >&2; exit 1; fi'";
        execEngine.exec(cmd);
    }

    function refreshStatus() {
        runCmd("status --json", "status");
    }

    function checkDoctor() {
        runCmd("doctor --json", "doctor");
    }

    function refreshPeers() {
        if (!root.receiving) return;
        runCmd("peers --json", "peers");
    }

    function scanPeersActive() {
        if (!root.receiving || root.peerScanBusy) return;
        root.peerScanBusy = true;
        runCmd("peers -n --json", "peers");
    }

    function turnOn(duration) {
        root.busy = true;
        runCmd("on " + (duration || "10m"), "action");
        statusTimer.restart();
    }

    function turnOff() {
        root.busy = true;
        runCmd("off", "action");
        statusTimer.restart();
    }

    function toggleReceiving() {
        if (root.receiving) root.turnOff();
        else root.turnOn("10m");
    }

    function setAudience(mode) {
        runCmd("visibility " + mode, "action");
    }

    function chooseDirectory() {
        runCmd("dir --pick", "action");
    }

    function sendFilesTo(mac, name) {
        runCmd("send --pick --to " + mac, "send");
    }

    function toggleSound() {
        root.soundMuted = !root.soundMuted;
        runCmd("sound " + (root.soundMuted ? "off" : "on"), "action");
    }

    function handleResult(cmd, stdout, stderr, exitCode) {
        root.busy = false;

        if (cmd.indexOf("status --json") !== -1) {
            try {
                var json = JSON.parse(stdout.trim());
                root.receiving = json.receiving === true;
                root.visibility = (json.visible === true) ? 1 : (json.visible === false ? 0 : -1);
                root.remaining = json.remaining !== null ? json.remaining : -1;
                root.deviceName = json.name || "";
                root.downloadDir = json.dir || "";
                root.audience = json.visibility || "everyone";
                root.senders = json.senders || 0;
                root.soundMuted = json.sound === false;
            } catch (e) {
                console.warn("ArchDrop JSON parse error:", e);
            }
        } else if (cmd.indexOf("doctor --json") !== -1) {
            try {
                var d = JSON.parse(stdout.trim());
                var cIssue = "";
                var hIssue = "";
                if (d.missing && d.missing.length > 0) {
                    for (var i = 0; i < d.missing.length; i++) {
                        if (d.missing[i].id === "radio") {
                            cIssue = d.missing[i].say;
                        } else if (d.missing[i].id === "hardware") {
                            hIssue = d.missing[i].say;
                        }
                    }
                }
                root.channelIssue = cIssue;
                root.hardwareIssue = hIssue;
            } catch (e) {
                // Ignore doctor parse errors
            }
        } else if (cmd.indexOf("peers") !== -1) {
            root.peerScanBusy = false;
            try {
                var plist = JSON.parse(stdout.trim());
                if (Array.isArray(plist)) {
                    root.peers = plist;
                }
            } catch (e) {
                // peers might be empty
            }
        } else if (cmd.indexOf("send --pick") !== -1) {
            // refresh status after send
            root.refreshStatus();
        }
    }

    onExpandedChanged: {
        if (expanded) {
            setAudience("everyone");
            refreshStatus();
        }
    }

    Component.onCompleted: {
        setAudience("everyone");
        refreshStatus();
        checkDoctor();
    }
}
