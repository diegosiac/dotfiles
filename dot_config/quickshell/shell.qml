import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property int activeWorkspace: 1
    property string networkText: "󰤭 --"
    property string volumeText: "󰕿 --"
    property string batteryText: ""

    readonly property color bg: "#111318"
    readonly property color islandBg: "#1c2028"
    readonly property color islandBorder: "#3a4050"
    readonly property color text: "#f4f4f5"
    readonly property color muted: "#b8beca"
    readonly property color dim: "#7f8796"
    readonly property color accent: "#8aadf4"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            implicitHeight: 46
            color: "transparent"

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

            exclusiveZone: 55

            Item {
                anchors.fill: parent

                Rectangle {
                    id: workspacesIsland
                    width: workspacesRow.implicitWidth + 16
                    height: 34
                    radius: 17
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

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
                                color: root.activeWorkspace === modelData ? root.accent : (workspaceMouse.containsMouse ? "#2a2f3a" : "transparent")

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: root.activeWorkspace === modelData ? root.bg : root.dim
                                    font.family: "Inter"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: workspaceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: switchWorkspace.exec(["hyprctl", "dispatch", "workspace", modelData.toString()])
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: clockIsland
                    width: clockText.implicitWidth + 30
                    height: 34
                    radius: 17
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.centerIn: parent

                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(clock.date, "ddd d · HH:mm")
                        color: root.text
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    id: statusIsland
                    width: statusRow.implicitWidth + 26
                    height: 34
                    radius: 17
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 16

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.networkText
                            color: root.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openNetworkSettings.exec(["sh", "-c", "command -v nm-connection-editor >/dev/null 2>&1 && nm-connection-editor >/dev/null 2>&1 &"])
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.volumeText
                            color: root.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: openVolumeControl.exec(["sh", "-c", "command -v pavucontrol >/dev/null 2>&1 && pavucontrol >/dev/null 2>&1 &"])
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            visible: root.batteryText.length > 0
                            text: root.batteryText
                            color: root.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: switchWorkspace
    }

    Process {
        id: openNetworkSettings
    }

    Process {
        id: openVolumeControl
    }

    Process {
        id: workspaceProc
        command: ["sh", "-c", "hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf 1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.activeWorkspace = parseInt(this.text.trim()) || 1
        }
    }

    Process {
        id: networkProc
        command: ["sh", "-c", "if command -v nmcli >/dev/null 2>&1; then nmcli -t -f TYPE,STATE,CONNECTION device | awk -F: '$2 == \"connected\" { icon=($1 == \"wifi\") ? \"󰤨\" : (($1 == \"ethernet\") ? \"󰈀\" : \"󰌘\"); print icon \" \" $3; found=1; exit } END { if (!found) print \"󰤭 --\" }'; else printf '󰤭 --'; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.networkText = this.text.trim() || "󰤭 --"
        }
    }

    Process {
        id: volumeProc
        command: ["sh", "-c", "if command -v wpctl >/dev/null 2>&1; then wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{ vol=int($2 * 100); icon=($0 ~ /MUTED/) ? \"󰝟\" : ((vol < 35) ? \"󰕿\" : ((vol < 70) ? \"󰖀\" : \"󰕾\")); muted=($0 ~ /MUTED/) ? \" muted\" : \"\"; printf \"%s %d%%%s\", icon, vol, muted }'; else printf '󰕿 --'; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.volumeText = this.text.trim() || "󰕿 --"
        }
    }

    Process {
        id: batteryProc
        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do [ -d \"$b\" ] || continue; cap=$(cat \"$b/capacity\" 2>/dev/null); status=$(cat \"$b/status\" 2>/dev/null); [ -n \"$cap\" ] || continue; if [ \"$status\" = Charging ]; then icon=󰂄; elif [ \"$cap\" -lt 20 ]; then icon=󰁺; elif [ \"$cap\" -lt 40 ]; then icon=󰁼; elif [ \"$cap\" -lt 60 ]; then icon=󰁾; elif [ \"$cap\" -lt 80 ]; then icon=󰂀; else icon=󰁹; fi; printf '%s %s%%' \"$icon\" \"$cap\"; exit; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.batteryText = this.text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: workspaceProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            networkProc.running = true
            volumeProc.running = true
            batteryProc.running = true
        }
    }
}
