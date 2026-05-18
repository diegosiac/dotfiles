import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property int activeWorkspace: 1
    property string networkText: "NET --"
    property string volumeText: "VOL --"
    property string batteryText: ""

    readonly property color bg: "#15171c"
    readonly property color islandBg: "#20232a"
    readonly property color islandBorder: "#343842"
    readonly property color text: "#f2f2f3"
    readonly property color muted: "#a8adb7"
    readonly property color accent: "#8aadf4"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            implicitHeight: 44
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
            }

            margins {
                top: 8
                left: 12
                right: 12
            }

            exclusiveZone: 52

            Item {
                anchors.fill: parent

                Rectangle {
                    id: workspacesIsland
                    width: workspacesRow.implicitWidth + 14
                    height: 32
                    radius: 16
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    RowLayout {
                        id: workspacesRow
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: [1, 2, 3, 4, 5, 6, 7]

                            Rectangle {
                                required property int modelData

                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                color: root.activeWorkspace === modelData ? root.accent : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: root.activeWorkspace === modelData ? root.bg : root.muted
                                    font.family: "Inter"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: switchWorkspace.exec(["hyprctl", "dispatch", "workspace", modelData.toString()])
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: clockIsland
                    width: clockText.implicitWidth + 28
                    height: 32
                    radius: 16
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.centerIn: parent

                    Text {
                        id: clockText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                        color: root.text
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    id: statusIsland
                    width: statusRow.implicitWidth + 24
                    height: 32
                    radius: 16
                    color: root.islandBg
                    border.color: root.islandBorder
                    border.width: 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 14

                        Text {
                            text: root.networkText
                            color: root.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.volumeText
                            color: root.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
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
        id: workspaceProc
        command: ["sh", "-c", "hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf 1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.activeWorkspace = parseInt(this.text.trim()) || 1
        }
    }

    Process {
        id: networkProc
        command: ["sh", "-c", "if command -v nmcli >/dev/null 2>&1; then nmcli -t -f TYPE,STATE,CONNECTION device | awk -F: '$2 == \"connected\" { print toupper($1) \" \" $3; found=1; exit } END { if (!found) print \"NET --\" }'; else printf 'NET --'; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.networkText = this.text.trim() || "NET --"
        }
    }

    Process {
        id: volumeProc
        command: ["sh", "-c", "if command -v wpctl >/dev/null 2>&1; then wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{ vol=int($2 * 100); muted=($0 ~ /MUTED/) ? \" MUTED\" : \"\"; printf \"VOL %d%%%s\", vol, muted }'; else printf 'VOL --'; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.volumeText = this.text.trim() || "VOL --"
        }
    }

    Process {
        id: batteryProc
        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do [ -d \"$b\" ] || continue; cap=$(cat \"$b/capacity\" 2>/dev/null); status=$(cat \"$b/status\" 2>/dev/null); [ -n \"$cap\" ] && { printf 'BAT %s%% %s' \"$cap\" \"$status\"; exit; }; done"]
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
