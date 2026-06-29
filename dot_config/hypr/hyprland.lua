-- Minimal Hyprland session for VM validation.
-- Current Hyprland uses Lua config at ~/.config/hypr/hyprland.lua.

local mainMod = "SUPER"
local terminal = "alacritty"
local launcher = "walker"
local browser = "zen-browser"

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("GTK_THEME", "WhiteSur-Dark")

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE GTK_THEME")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE GTK_THEME")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("swaync")
    hl.exec_cmd("xsettingsd")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("$HOME/.local/bin/set-wallpaper")
    hl.exec_cmd("elephant")
    hl.exec_cmd("walker --gapplication-service")
    hl.exec_cmd("quickshell")
end)

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
    },
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 1,
        col = {
            active_border = "rgba(c8d3d5ff)",
            inactive_border = "rgba(3b4244aa)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 5,
        active_opacity = 1.0,
        inactive_opacity = 0.96,
        fullscreen_opacity = 1.0,
        blur = {
            enabled = true,
            size = 5,
            passes = 1,
            ignore_opacity = true,
            new_optimizations = true,
            xray = true,
            special = false,
            popups = true,
            popups_ignorealpha = 0.60,
            input_methods = false,
            input_methods_ignorealpha = 0.20,
            contrast = 0.8916,
            brightness = 1.0,
            vibrancy = 0.1696,
            vibrancy_darkness = 0.0,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
    },
})

hl.curve("workspaceEase", {
    type = "bezier",
    points = { { 0.16, 1.0 }, { 0.30, 1.0 } },
})

hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 2.5,
    bezier = "workspaceEase",
    style = "fade",
})

hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 2.5,
    bezier = "workspaceEase",
    style = "popin 96%",
})

hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2.0,
    bezier = "workspaceEase",
    style = "popin 98%",
})

hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 2.5,
    bezier = "workspaceEase",
})

hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 2.5,
    bezier = "workspaceEase",
    style = "fade",
})

-- Core keyboard workflow.
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(launcher))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot-edit"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())

-- Window management.
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + T", hl.dsp.layout("togglesplit"))

-- Keyboard-first focus and movement.
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + Left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + Up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + Down", hl.dsp.window.move({ direction = "down" }))

-- Mouse fallback for emergency window manipulation.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Workspaces.
for i = 1, 7 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Audio, brightness, and media keys.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%- --min-value=1"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"), { locked = true })
