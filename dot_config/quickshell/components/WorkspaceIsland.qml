import QtQuick
import QtQuick.Layouts

Rectangle {
    id: island

    required property var service
    property color bg: "#111318"
    property color islandBg: "#1c2028"
    property color islandBorder: "#3a4050"
    property color dim: "#7f8796"
    property color accent: "#8aadf4"

    width: workspacesRow.implicitWidth + 16
    height: 34
    radius: 17
    color: islandBg
    border.color: islandBorder
    border.width: 1

    RowLayout {
        id: workspacesRow

        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: [1, 2, 3, 4, 5, 6, 7]

            Rectangle {
                required property int modelData

                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                radius: 13
                color: island.service.activeWorkspace === modelData ? island.accent : (workspaceMouse.containsMouse ? "#2a2f3a" : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: island.service.activeWorkspace === modelData ? island.bg : island.dim
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: workspaceMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: island.service.switchWorkspace(modelData)
                }

            }

        }

    }

}
