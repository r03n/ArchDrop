pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: compactRoot

    property var plasmoidItem

    Layout.minimumWidth: Kirigami.Units.gridUnit * 1.6
    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.6
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    readonly property bool isReceiving: plasmoidItem ? plasmoidItem.receiving : false
    readonly property bool isVisible: plasmoidItem ? (plasmoidItem.visibility === 1) : false
    readonly property int remainingSecs: plasmoidItem ? plasmoidItem.remaining : -1
    readonly property string channelAlert: plasmoidItem ? plasmoidItem.channelIssue : ""

    readonly property color statusColor: {
        if (channelAlert !== "") return Kirigami.Theme.neutralTextColor; // Amber
        if (isReceiving && isVisible) return Kirigami.Theme.highlightColor;
        if (isReceiving && !isVisible) return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.textColor;
    }

    ArchDropIcon {
        id: iconItem
        anchors.centerIn: parent
        iconSize: Math.min(parent.width, parent.height) * 0.8
        color: compactRoot.statusColor
        active: compactRoot.isReceiving
        crossed: compactRoot.channelAlert !== ""
        drifting: plasmoidItem ? plasmoidItem.busy : false
    }

    // Badge showing remaining time
    Rectangle {
        id: badge
        visible: compactRoot.isReceiving && compactRoot.remainingSecs > 0
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: -2
        anchors.rightMargin: -2
        height: Math.round(Kirigami.Units.gridUnit * 0.85)
        width: Math.max(height, badgeText.implicitWidth + 6)
        radius: height / 2
        color: Kirigami.Theme.highlightColor

        PlasmaComponents.Label {
            id: badgeText
            anchors.centerIn: parent
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.55)
            font.bold: true
            color: Kirigami.Theme.highlightedTextColor
            text: {
                var s = compactRoot.remainingSecs;
                if (s <= 0) return "";
                if (s >= 3600) return Math.ceil(s / 3600) + "h";
                return Math.ceil(s / 60) + "m";
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                if (plasmoidItem) {
                    plasmoidItem.expanded = !plasmoidItem.expanded;
                }
            } else if (mouse.button === Qt.MiddleButton) {
                if (plasmoidItem) {
                    plasmoidItem.toggleReceiving();
                }
            }
        }
    }
}
