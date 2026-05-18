import QtQuick
import Quickshell

PanelWindow {
    id: bar

    required property var modelData
    required property var service
    readonly property color bg: "#111318"
    readonly property color islandBg: "#1c2028"
    readonly property color islandBorder: "#3a4050"
    readonly property color text: "#f4f4f5"
    readonly property color muted: "#b8beca"
    readonly property color dim: "#7f8796"
    readonly property color accent: "#8aadf4"

    screen: modelData
    implicitHeight: 46
    color: "transparent"
    exclusiveZone: 55

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 9
        left: 14
        right: 14
    }

    Item {
        anchors.fill: parent

        WorkspaceIsland {
            service: bar.service
            bg: bar.bg
            islandBg: bar.islandBg
            islandBorder: bar.islandBorder
            dim: bar.dim
            accent: bar.accent
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        ClockIsland {
            islandBg: bar.islandBg
            islandBorder: bar.islandBorder
            textColor: bar.text
            anchors.centerIn: parent
        }

        StatusIsland {
            id: statusIsland

            service: bar.service
            islandBg: bar.islandBg
            islandBorder: bar.islandBorder
            muted: bar.muted
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onClicked: controlCenter.visible = !controlCenter.visible
        }

        ControlCenter {
            id: controlCenter

            service: bar.service
            bg: bar.bg
            islandBg: bar.islandBg
            islandBorder: bar.islandBorder
            textColor: bar.text
            muted: bar.muted
            dim: bar.dim
            accent: bar.accent
            anchor.window: bar
            anchor.rect.x: bar.width - width
            anchor.rect.y: statusIsland.y + statusIsland.height + 8
        }

    }

}
