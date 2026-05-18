import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: popup

    required property var service
    property color bg: "#111318"
    property color islandBg: "#1c2028"
    property color islandBorder: "#3a4050"
    property color textColor: "#f4f4f5"
    property color muted: "#b8beca"
    property color dim: "#7f8796"
    property color accent: "#8aadf4"
    property bool confirmReboot: false
    property bool confirmShutdown: false

    function armReboot() {
        confirmReboot = true;
        confirmShutdown = false;
        confirmResetTimer.restart();
    }

    function armShutdown() {
        confirmShutdown = true;
        confirmReboot = false;
        confirmResetTimer.restart();
    }

    width: 330
    height: content.implicitHeight + 28
    color: "transparent"
    grabFocus: true
    onVisibleChanged: {
        if (visible) {
            service.refreshAll();
        } else {
            confirmReboot = false;
            confirmShutdown = false;
            confirmResetTimer.stop();
        }
    }

    Timer {
        id: confirmResetTimer

        interval: 5000
        onTriggered: {
            popup.confirmReboot = false;
            popup.confirmShutdown = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: popup.bg
        border.color: popup.islandBorder
        border.width: 1

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: 14
            spacing: 13

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Control Center"
                    color: popup.textColor
                    font.family: "Inter"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    text: Qt.formatDateTime(new Date(), "HH:mm")
                    color: popup.dim
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                radius: 14
                color: popup.islandBg

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: popup.service.networkText
                            color: popup.textColor
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: popup.service.networkDetail
                            color: popup.dim
                            font.family: "Inter"
                            font.pixelSize: 11
                        }

                    }

                    ControlButton {
                        label: "Network"
                        bg: "#252b36"
                        hoverBg: "#303849"
                        textColor: popup.textColor
                        onClicked: popup.service.openNetworkSettings()
                    }

                }

            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: popup.service.volumePercent < 0 ? "Volume unavailable" : (popup.service.volumeMuted ? "Volume muted" : "Volume " + popup.service.volumePercent + "%")
                        color: popup.muted
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    ControlButton {
                        label: "Mixer"
                        enabled: popup.service.volumePercent >= 0
                        bg: enabled ? "#252b36" : "#1a1e26"
                        hoverBg: enabled ? "#303849" : "#1a1e26"
                        textColor: enabled ? popup.textColor : popup.dim
                        onClicked: popup.service.openVolumeControl()
                    }

                    ControlButton {
                        label: popup.service.volumeMuted ? "Unmute" : "Mute"
                        enabled: popup.service.volumePercent >= 0
                        bg: !enabled ? "#1a1e26" : (popup.service.volumeMuted ? "#513039" : "#252b36")
                        hoverBg: !enabled ? "#1a1e26" : (popup.service.volumeMuted ? "#653945" : "#303849")
                        textColor: enabled ? popup.textColor : popup.dim
                        onClicked: popup.service.toggleMute()
                    }

                }

                Slider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: Math.max(0, popup.service.volumePercent)
                    enabled: popup.service.volumePercent >= 0
                    onMoved: popup.service.setVolume(value)
                }

            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: popup.service.brightnessAvailable
                spacing: 7

                Text {
                    text: "Brightness " + popup.service.brightnessPercent + "%"
                    color: popup.muted
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Slider {
                    Layout.fillWidth: true
                    from: 1
                    to: 100
                    value: popup.service.brightnessPercent
                    onMoved: popup.service.setBrightness(value)
                }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                visible: popup.service.batteryText.length > 0
                radius: 14
                color: popup.islandBg

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12

                    Text {
                        Layout.fillWidth: true
                        text: popup.service.batteryText
                        color: popup.textColor
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: popup.service.batteryDetail
                        color: popup.dim
                        font.family: "Inter"
                        font.pixelSize: 11
                    }

                }

            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ControlButton {
                    Layout.fillWidth: true
                    label: "Lock"
                    onClicked: popup.service.lock()
                }

                ControlButton {
                    Layout.fillWidth: true
                    label: "Logout"
                    onClicked: popup.service.logout()
                }

            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ControlButton {
                    Layout.fillWidth: true
                    label: popup.confirmReboot ? "Confirm reboot" : "Reboot"
                    bg: popup.confirmReboot ? "#5a342d" : "#252b36"
                    hoverBg: popup.confirmReboot ? "#754034" : "#303849"
                    onClicked: {
                        if (popup.confirmReboot) {
                            popup.service.reboot();
                            return;
                        }

                        popup.armReboot();
                    }
                }

                ControlButton {
                    Layout.fillWidth: true
                    label: popup.confirmShutdown ? "Confirm shutdown" : "Shutdown"
                    bg: popup.confirmShutdown ? "#5a2d36" : "#252b36"
                    hoverBg: popup.confirmShutdown ? "#753846" : "#303849"
                    onClicked: {
                        if (popup.confirmShutdown) {
                            popup.service.shutdown();
                            return;
                        }

                        popup.armShutdown();
                    }
                }

            }

        }

    }

}
