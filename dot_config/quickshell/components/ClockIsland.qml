import QtQuick
import Quickshell.Io

Rectangle {
    id: island

    property color islandBg: "#1c2028"
    property color islandBorder: "#3a4050"
    property color textColor: "#f4f4f5"

    width: clockText.implicitWidth + 30
    height: 34
    radius: 17
    color: islandBg
    border.color: islandBorder
    border.width: 1

    Text {
        id: clockText

        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd d · HH:mm")
        color: island.textColor
        font.family: "Inter"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

}
