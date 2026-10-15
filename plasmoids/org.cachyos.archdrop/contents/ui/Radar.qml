pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents

Item {
    id: root

    property var peers: []
    property bool scanning: false
    property bool muted: false
    property string soundDir: ""
    property color foregroundColor: Kirigami.Theme.textColor
    property color highlightColor: Kirigami.Theme.highlightColor

    signal muteToggled()
    signal peerClicked(string mac, string name)

    implicitWidth: Kirigami.Units.gridUnit * 15
    implicitHeight: width

    readonly property bool active: visible && scanning
    readonly property real radius: Math.max(0, Math.min(width, height) / 2 - Kirigami.Units.gridUnit * 0.5)
    property real sweepAngle: 0
    property real previousSweepAngle: -1

    ListModel {
        id: contacts
    }

    // Concentric range circles
    Shape {
        anchors.fill: parent
        asynchronous: true

        ShapePath {
            strokeColor: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.15)
            strokeWidth: 1.2
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.radius * 0.33; radiusY: root.radius * 0.33
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.15)
            strokeWidth: 1.2
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.radius * 0.66; radiusY: root.radius * 0.66
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.25)
            strokeWidth: 1.5
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.radius; radiusY: root.radius
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // Rotating Sweep line and sector gradient
    Item {
        id: sweepContainer
        anchors.fill: parent
        visible: root.active

        NumberAnimation on rotation {
            from: 0; to: 360; duration: 4000
            loops: Animation.Infinite
            running: root.active
        }

        onRotationChanged: {
            root.sweepAngle = rotation;
            root.advanceSweep();
        }

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.6)
                strokeWidth: 1.5
                fillColor: "transparent"
                startX: root.width / 2; startY: root.height / 2
                PathLine { x: root.width / 2; y: root.height / 2 - root.radius }
            }
        }
    }

    // Contact Dots
    Repeater {
        id: contactRepeater
        model: contacts

        delegate: Item {
            id: peerDelegate
            required property string mac
            required property string peerName
            required property real bearing
            required property real strength
            required property bool present

            readonly property real dist: root.radius * (1.0 - Math.max(0.15, Math.min(0.9, strength)))
            readonly property real rad: (bearing - 90) * Math.PI / 180.0
            x: root.width / 2 + dist * Math.cos(rad) - width / 2
            y: root.height / 2 + dist * Math.sin(rad) - height / 2
            width: Kirigami.Units.gridUnit * 1.5
            height: Kirigami.Units.gridUnit * 1.5

            Rectangle {
                id: dot
                anchors.centerIn: parent
                width: Kirigami.Units.gridUnit * 0.6
                height: width
                radius: width / 2
                color: root.highlightColor

                SequentialAnimation {
                    id: pingAnim
                    PropertyAnimation { target: dot; property: "scale"; from: 1.0; to: 2.2; duration: 250; easing.type: Easing.OutQuad }
                    PropertyAnimation { target: dot; property: "scale"; from: 2.2; to: 1.0; duration: 350; easing.type: Easing.InQuad }
                }
            }

            PlasmaComponents.Label {
                anchors.top: dot.bottom
                anchors.horizontalCenter: dot.horizontalCenter
                anchors.topMargin: 2
                text: peerDelegate.peerName !== "" ? peerDelegate.peerName : peerDelegate.mac.substring(9)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
                font.bold: true
                color: root.foregroundColor
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.peerClicked(peerDelegate.mac, peerDelegate.peerName)
            }

            function sweepHit() {
                pingAnim.restart();
            }
        }
    }

    // Center icon
    ArchDropIcon {
        anchors.centerIn: parent
        iconSize: Kirigami.Units.gridUnit * 1.2
        color: root.highlightColor
        active: root.active
    }

    // Speaker mute toggle in bottom-right corner
    PlasmaComponents.ToolButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        icon.name: root.muted ? "audio-volume-muted" : "audio-volume-high"
        onClicked: root.muteToggled()
    }

    function advanceSweep() {
        var current = (sweepAngle + 360) % 360;
        var previous = previousSweepAngle;
        previousSweepAngle = current;
        if (!active || previous < 0) return;
        var travelled = (current - previous + 360) % 360;
        if (travelled === 0) return;

        for (var i = 0; i < contactRepeater.count; i++) {
            var contact = contactRepeater.itemAt(i);
            if (!contact) continue;
            var angle = (Math.atan2(contact.x - width / 2, height / 2 - contact.y) * 180 / Math.PI + 360) % 360;
            var distance = (angle - previous + 360) % 360;
            if (distance > 0 && distance <= travelled) {
                contact.sweepHit();
                if (!root.muted && root.soundDir !== "") {
                    // sound ping
                }
            }
        }
    }

    function angleFor(mac) {
        var hash = 0;
        for (var i = 0; i < mac.length; i++) hash = (hash * 31 + mac.charCodeAt(i)) >>> 0;
        return hash % 360;
    }

    function reconcile() {
        var snapshot = peers || [];
        var seen = {};
        for (var i = 0; i < snapshot.length; i++) {
            var peer = snapshot[i];
            if (!peer || !peer.mac) continue;
            var mac = peer.mac.toLowerCase();
            seen[mac] = true;
            var strength = (peer.rssi !== null && typeof peer.rssi === "number")
                ? Math.max(0.1, Math.min(1.0, (peer.rssi + 95) / 55.0))
                : 0.5;
            var name = peer.name || "";

            var found = -1;
            for (var j = 0; j < contacts.count; j++) {
                if (contacts.get(j).mac === mac) { found = j; break; }
            }
            if (found < 0) {
                contacts.append({ mac: mac, peerName: name, bearing: angleFor(mac), strength: strength, present: true });
            } else {
                contacts.set(found, { mac: mac, peerName: name, bearing: angleFor(mac), strength: strength, present: true });
            }
        }
        for (var k = contacts.count - 1; k >= 0; k--) {
            if (!seen[contacts.get(k).mac]) {
                contacts.remove(k);
            }
        }
    }

    onPeersChanged: reconcile()
    Component.onCompleted: reconcile()
}
