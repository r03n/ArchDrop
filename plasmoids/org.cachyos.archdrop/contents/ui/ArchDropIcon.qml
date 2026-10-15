pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color color: Qt.rgba(1, 1, 1, 0.9)
    property real iconSize: 22
    property bool crossed: false
    property bool drifting: false
    property bool active: false

    implicitWidth: iconSize
    implicitHeight: iconSize

    Item {
        id: container
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.iconSize / 24

        SequentialAnimation on anchors.verticalCenterOffset {
            running: root.drifting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 1.6; duration: 750; easing.type: Easing.OutSine }
            NumberAnimation { to: -1.6; duration: 1500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 750; easing.type: Easing.InSine }
        }

        SequentialAnimation on rotation {
            running: root.drifting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 4; duration: 950; easing.type: Easing.OutSine }
            NumberAnimation { to: -4; duration: 1900; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 950; easing.type: Easing.InSine }
        }

        Shape {
            anchors.fill: parent

            // Upper inverted triangle
            ShapePath {
                strokeColor: root.color
                fillColor: root.active ? root.color : "transparent"
                strokeWidth: 1.8
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M2 4h20L12 14z" }
            }

            // Lower tray box
            ShapePath {
                strokeColor: root.color
                fillColor: "transparent"
                strokeWidth: 1.8
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M7 16h10v5H7z" }
            }

            // Cross line when hardware/channel is unavailable
            ShapePath {
                strokeColor: root.crossed ? Qt.rgba(0.9, 0.2, 0.2, 0.9) : "transparent"
                fillColor: "transparent"
                strokeWidth: 2.0
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M3 21L21 3" }
            }
        }
    }
}
