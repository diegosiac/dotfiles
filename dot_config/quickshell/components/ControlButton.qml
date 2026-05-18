import QtQuick

Rectangle {
    id: button

    property string label: ""
    property color bg: "#252b36"
    property color hoverBg: "#303849"
    property color textColor: "#f4f4f5"

    signal clicked()

    implicitWidth: buttonText.implicitWidth + 22
    implicitHeight: 32
    radius: 10
    color: mouse.containsMouse ? hoverBg : bg

    Text {
        id: buttonText

        anchors.centerIn: parent
        text: button.label
        color: button.textColor
        font.family: "Inter"
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

}
