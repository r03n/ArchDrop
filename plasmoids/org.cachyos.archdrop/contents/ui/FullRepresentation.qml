pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: fullRoot

    property var plasmoidItem

    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Kirigami.Units.gridUnit * 27

    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    readonly property bool isReceiving: plasmoidItem ? plasmoidItem.receiving : false
    readonly property bool isVisible: plasmoidItem ? (plasmoidItem.visibility === 1) : false
    readonly property int remainingSecs: plasmoidItem ? plasmoidItem.remaining : -1
    readonly property string deviceName: plasmoidItem ? plasmoidItem.deviceName : ""
    readonly property string downloadDir: plasmoidItem ? plasmoidItem.downloadDir : ""
    readonly property string currentAudience: plasmoidItem ? plasmoidItem.audience : "everyone"
    readonly property string channelAlert: plasmoidItem ? plasmoidItem.channelIssue : ""

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: Kirigami.Units.largeSpacing

            // Top Header: App Title & Status
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                ArchDropIcon {
                    iconSize: Kirigami.Units.gridUnit * 1.5
                    color: isReceiving ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                    active: isReceiving
                }

                PlasmaComponents.Label {
                    text: i18n("ArchDrop")
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 1.1)
                }

                Item { Layout.fillWidth: true }

                // Status Pill
                Rectangle {
                    height: Kirigami.Units.gridUnit * 1.3
                    width: statusLabel.implicitWidth + Kirigami.Units.gridUnit
                    radius: height / 2
                    color: {
                        if (isReceiving && isVisible) return Qt.rgba(0.1, 0.7, 0.3, 0.2);
                        if (isReceiving) return Qt.rgba(0.2, 0.5, 0.9, 0.2);
                        return Qt.rgba(0.5, 0.5, 0.5, 0.15);
                    }

                    PlasmaComponents.Label {
                        id: statusLabel
                        anchors.centerIn: parent
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.7)
                        font.bold: true
                        color: {
                            if (isReceiving && isVisible) return Kirigami.Theme.positiveTextColor;
                            if (isReceiving) return Kirigami.Theme.highlightColor;
                            return Kirigami.Theme.disabledTextColor;
                        }
                        text: {
                            if (isReceiving) {
                                if (remainingSecs > 0) {
                                    var m = Math.ceil(remainingSecs / 60);
                                    return i18n("On (%1m left)", m);
                                }
                                return i18n("On (Active)");
                            }
                            return i18n("Ready");
                        }
                    }
                }
            }

            // Exclusive Mode Notice (Visible when receiving)
            Rectangle {
                visible: isReceiving
                Layout.fillWidth: true
                radius: Kirigami.Units.smallSpacing
                color: Qt.rgba(0.2, 0.5, 0.9, 0.12)
                border.color: Qt.rgba(0.2, 0.5, 0.9, 0.3)
                border.width: 1
                implicitHeight: exclusiveRow.implicitHeight + Kirigami.Units.smallSpacing * 2

                RowLayout {
                    id: exclusiveRow
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "network-wireless-symbolic"
                        implicitWidth: Kirigami.Units.gridUnit * 1.2
                        implicitHeight: Kirigami.Units.gridUnit * 1.2
                        Layout.alignment: Qt.AlignVCenter
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: i18n("AirDrop Active (Exclusive Mode). Wi-Fi automatically reconnects when receiving stops.")
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.75)
                        color: Kirigami.Theme.highlightColor
                    }
                }
            }

            // Main Switch Card
            Kirigami.Card {
                Layout.fillWidth: true

                contentItem: RowLayout {
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: isReceiving ? i18n("Visible to Nearby Devices") : i18n("AirDrop Receiving is Off")
                        font.bold: true
                    }

                    PlasmaComponents.Switch {
                        checked: isReceiving
                        onToggled: {
                            if (plasmoidItem) {
                                if (checked) plasmoidItem.turnOn("10m");
                                else plasmoidItem.turnOff();
                            }
                        }
                    }
                }
            }


            // Duration Selection Buttons
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Stay visible for:")
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.75)
                    color: Kirigami.Theme.disabledTextColor
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: i18n("10 min")
                        onClicked: if (plasmoidItem) plasmoidItem.turnOn("10m")
                    }
                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: i18n("30 min")
                        onClicked: if (plasmoidItem) plasmoidItem.turnOn("30m")
                    }
                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: i18n("1 hour")
                        onClicked: if (plasmoidItem) plasmoidItem.turnOn("1h")
                    }
                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: i18n("1 file")
                        onClicked: if (plasmoidItem) plasmoidItem.turnOn("once")
                    }
                }
            }

            // Receiving Audience Info (Everyone Nearby)
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "system-users"
                    implicitWidth: Kirigami.Units.gridUnit
                    implicitHeight: Kirigami.Units.gridUnit
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Receiving from: Everyone Nearby")
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.8)
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            // Device Name & Download Folder info
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: i18n("They see you as:")
                        color: Kirigami.Theme.disabledTextColor
                    }
                    PlasmaComponents.Label {
                        text: deviceName !== "" ? deviceName : i18n("Unknown")
                        font.bold: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: i18n("Save files to:")
                        color: Kirigami.Theme.disabledTextColor
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: downloadDir
                    }
                    PlasmaComponents.ToolButton {
                        icon.name: "folder-open"
                        onClicked: if (plasmoidItem) plasmoidItem.chooseDirectory()
                    }
                }
            }

            // Radar & Nearby Devices
            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: i18n("Send to Peers")
                    font.bold: true
                }

                PlasmaComponents.ToolButton {
                    icon.name: (plasmoidItem && plasmoidItem.peerScanBusy) ? "view-process-all" : "view-refresh"
                    enabled: !(plasmoidItem && plasmoidItem.peerScanBusy)
                    onClicked: if (plasmoidItem) plasmoidItem.scanPeersActive()
                }
            }

            // Radar Canvas
            Radar {
                Layout.alignment: Qt.AlignHCenter
                peers: plasmoidItem ? plasmoidItem.peers : []
                scanning: isReceiving
                muted: plasmoidItem ? plasmoidItem.soundMuted : false
                onMuteToggled: if (plasmoidItem) plasmoidItem.toggleSound()
                onPeerClicked: (mac, name) => {
                    if (plasmoidItem) plasmoidItem.sendFilesTo(mac, name)
                }
            }

            // Nearby Peers List
            ListView {
                Layout.fillWidth: true
                implicitHeight: count > 0 ? Math.min(count * Kirigami.Units.gridUnit * 2.5, Kirigami.Units.gridUnit * 7) : Kirigami.Units.gridUnit * 2
                clip: true
                model: plasmoidItem ? plasmoidItem.peers : []

                delegate: PlasmaComponents.ItemDelegate {
                    required property var modelData

                    contentItem: RowLayout {
                        Kirigami.Icon {
                            source: "phone"
                            implicitWidth: Kirigami.Units.gridUnit * 1.2
                            implicitHeight: Kirigami.Units.gridUnit * 1.2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            PlasmaComponents.Label {
                                text: modelData.name || i18n("Apple Device")
                                font.bold: true
                            }
                            PlasmaComponents.Label {
                                text: modelData.mac || ""
                                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.65)
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }
                        PlasmaComponents.Button {
                            text: i18n("Send")
                            icon.name: "document-send"
                            onClicked: if (plasmoidItem) plasmoidItem.sendFilesTo(modelData.mac, modelData.name || "")
                        }
                    }
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: parent.count === 0
                    text: isReceiving ? i18n("Scanning for nearby devices…") : i18n("Turn on ArchDrop to discover peers")
                    color: Kirigami.Theme.disabledTextColor
                    font.italic: true
                }
            }
        }
    }
}
