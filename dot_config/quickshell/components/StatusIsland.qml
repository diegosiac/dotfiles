import QtQuick
import QtQuick.Layouts

Rectangle {
    id: island

    required property var service
    property color islandBg: "#1c2028"
    property color islandBorder: "#3a4050"
    property color muted: "#b8beca"

    signal clicked()

    width: statusRow.implicitWidth + 26
    height: 34
    radius: 17
    color: statusMouse.containsMouse ? "#202633" : islandBg
    border.color: islandBorder
    border.width: 1

    RowLayout {
        id: statusRow

        anchors.centerIn: parent
        spacing: 16

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: island.service.networkText
            color: island.muted
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: island.service.volumeText
            color: island.muted
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: island.service.batteryText.length > 0
            text: island.service.batteryText
            color: island.muted
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

    }

    MouseArea {
        id: statusMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: island.clicked()
    }

}
