import QtQuick

Rectangle {
    id: island

    property color islandBg: "#1c2028"
    property color islandBorder: "#3a4050"
    property color textColor: "#f4f4f5"
    property date currentDate: new Date()

    width: clockText.implicitWidth + 30
    height: 34
    radius: 17
    color: islandBg
    border.color: islandBorder
    border.width: 1

    Text {
        id: clockText

        anchors.centerIn: parent
        text: Qt.formatDateTime(island.currentDate, "ddd d · HH:mm")
        color: island.textColor
        font.family: "Inter"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: island.currentDate = new Date()
    }

}
