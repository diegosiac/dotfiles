import QtQuick
import Quickshell.Io

Item {
    id: service

    property int activeWorkspace: 1
    property string networkText: "󰤭 --"
    property string networkDetail: "Unavailable"
    property int volumePercent: -1
    property bool volumeMuted: false
    property string volumeText: "󰕿 --"
    property bool brightnessAvailable: false
    property int brightnessPercent: 50
    property string batteryText: ""
    property string batteryDetail: "No battery detected"

    function refreshAll() {
        workspaceProc.running = true;
        networkProc.running = true;
        volumeProc.running = true;
        brightnessProc.running = true;
        batteryProc.running = true;
    }

    function switchWorkspace(workspace) {
        switchWorkspaceProc.exec(["hyprctl", "dispatch", "workspace", workspace.toString()]);
    }

    function openNetworkSettings() {
        openProc.exec(["sh", "-c", "command -v nm-connection-editor >/dev/null 2>&1 && nm-connection-editor >/dev/null 2>&1 &"]);
    }

    function openVolumeControl() {
        openProc.exec(["sh", "-c", "command -v pavucontrol >/dev/null 2>&1 && pavucontrol >/dev/null 2>&1 &"]);
    }

    function setVolume(percent) {
        const clamped = Math.max(0, Math.min(100, Math.round(percent)));
        volumeSetProc.exec(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", clamped + "%"]);
        volumePercent = clamped;
        volumeRefreshDelay.restart();
    }

    function toggleMute() {
        volumeSetProc.exec(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        volumeRefreshDelay.restart();
    }

    function setBrightness(percent) {
        const clamped = Math.max(1, Math.min(100, Math.round(percent)));
        brightnessSetProc.exec(["brightnessctl", "set", clamped + "%"]);
        brightnessPercent = clamped;
        brightnessRefreshDelay.restart();
    }

    function lock() {
        powerProc.exec(["sh", "-c", "if command -v hyprlock >/dev/null 2>&1; then hyprlock; elif command -v loginctl >/dev/null 2>&1; then loginctl lock-session; fi"]);
    }

    function logout() {
        powerProc.exec(["hyprctl", "dispatch", "exit"]);
    }

    function reboot() {
        powerProc.exec(["systemctl", "reboot"]);
    }

    function shutdown() {
        powerProc.exec(["systemctl", "poweroff"]);
    }

    Process {
        id: switchWorkspaceProc
    }

    Process {
        id: openProc
    }

    Process {
        id: volumeSetProc
    }

    Process {
        id: brightnessSetProc
    }

    Process {
        id: powerProc
    }

    Process {
        id: workspaceProc

        command: ["sh", "-c", "hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf 1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: service.activeWorkspace = parseInt(this.text.trim()) || 1
        }

    }

    Process {
        id: networkProc

        command: ["sh", "-c", "if command -v nmcli >/dev/null 2>&1; then nmcli -t -f TYPE,STATE,CONNECTION device | awk -F: '$2 == \"connected\" { icon=($1 == \"wifi\") ? \"󰤨\" : (($1 == \"ethernet\") ? \"󰈀\" : \"󰌘\"); name=($3 == \"\") ? $1 : $3; print icon \" \" name; print $1 \" connected\"; found=1; exit } END { if (!found) { print \"󰤭 --\"; print \"Disconnected\" } }'; else printf '󰤭 --\\nNetworkManager unavailable'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                service.networkText = lines[0] || "󰤭 --";
                service.networkDetail = lines[1] || "Unavailable";
            }
        }

    }

    Process {
        id: volumeProc

        command: ["sh", "-c", "if command -v wpctl >/dev/null 2>&1; then out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null); if [ -n \"$out\" ]; then printf '%s\\n' \"$out\" | awk '{ vol=int($2 * 100); muted=($0 ~ /MUTED/) ? 1 : 0; icon=muted ? \"󰝟\" : ((vol < 35) ? \"󰕿\" : ((vol < 70) ? \"󰖀\" : \"󰕾\")); label=muted ? \" muted\" : \"\"; printf \"%s %d%%%s\\n%d\\n%d\", icon, vol, label, vol, muted }'; else printf '󰕿 --\\n-1\\n0'; fi; else printf '󰕿 --\\n-1\\n0'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                service.volumeText = lines[0] || "󰕿 --";
                service.volumePercent = parseInt(lines[1]);
                if (isNaN(service.volumePercent))
                    service.volumePercent = -1;

                service.volumeMuted = lines[2] === "1";
            }
        }

    }

    Process {
        id: brightnessProc

        command: ["sh", "-c", "if command -v brightnessctl >/dev/null 2>&1 && ls /sys/class/backlight/* >/dev/null 2>&1; then max=$(brightnessctl max 2>/dev/null); cur=$(brightnessctl get 2>/dev/null); if [ -n \"$max\" ] && [ \"$max\" -gt 1 ] && [ -n \"$cur\" ]; then pct=$((cur * 100 / max)); [ \"$pct\" -lt 1 ] && pct=1; printf '%s' \"$pct\"; else printf unavailable; fi; else printf unavailable; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(this.text.trim());
                service.brightnessAvailable = !isNaN(value);
                if (service.brightnessAvailable)
                    service.brightnessPercent = Math.max(1, Math.min(100, value));

            }
        }

    }

    Process {
        id: batteryProc

        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do [ -d \"$b\" ] || continue; cap=$(cat \"$b/capacity\" 2>/dev/null); status=$(cat \"$b/status\" 2>/dev/null); [ -n \"$cap\" ] || continue; if [ \"$status\" = Charging ]; then icon=󰂄; elif [ \"$cap\" -lt 20 ]; then icon=󰁺; elif [ \"$cap\" -lt 40 ]; then icon=󰁼; elif [ \"$cap\" -lt 60 ]; then icon=󰁾; elif [ \"$cap\" -lt 80 ]; then icon=󰂀; else icon=󰁹; fi; printf '%s %s%%\\n%s' \"$icon\" \"$cap\" \"${status:-Unknown}\"; exit; done"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                service.batteryText = lines[0] || "";
                service.batteryDetail = lines[1] || "No battery detected";
            }
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
            networkProc.running = true;
            volumeProc.running = true;
            brightnessProc.running = true;
            batteryProc.running = true;
        }
    }

    Timer {
        id: volumeRefreshDelay

        interval: 250
        onTriggered: volumeProc.running = true
    }

    Timer {
        id: brightnessRefreshDelay

        interval: 250
        onTriggered: brightnessProc.running = true
    }

}
