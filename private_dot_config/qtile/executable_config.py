#       █████████     ███████    ███████████ █████ █████ ███████████ █████ █████       ██████████
#      ███░░░░░███  ███░░░░░███ ░█░░░░░░███ ░░███ ░░███ ░█░░░███░░░█░░███ ░░███       ░░███░░░░░█
#     ███     ░░░  ███     ░░███░     ███░   ░░███ ███  ░   ░███  ░  ░███  ░███        ░███  █ ░
#    ░███         ░███      ░███     ███      ░░█████       ░███     ░███  ░███        ░██████
#    ░███         ░███      ░███    ███        ░░███        ░███     ░███  ░███        ░███░░█
#    ░░███     ███░░███     ███   ████     █    ░███        ░███     ░███  ░███      █ ░███ ░   █
#     ░░█████████  ░░░███████░   ███████████    █████       █████    █████ ███████████ ██████████
#      ░░░░░░░░░     ░░░░░░░    ░░░░░░░░░░░    ░░░░░       ░░░░░    ░░░░░ ░░░░░░░░░░░ ░░░░░░░░░░
#
#                                                                                    - DARKKAL44


import subprocess
import os
from libqtile import bar, layout, widget, hook, qtile
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy


mod = "mod4"
terminal = "ghostty"

# █▄▀ █▀▀ █▄█ █▄▄ █ █▄░█ █▀▄ █▀
# █░█ ██▄ ░█░ █▄█ █ █░▀█ █▄▀ ▄█


keys = [
    #  D E F A U L T
    # Switch between windows in current stack pane
    Key([mod], "h", lazy.layout.left(), desc="Move focus to left"),
    Key([mod], "l", lazy.layout.right(), desc="Move focus to right"),
    Key([mod], "j", lazy.layout.down(), desc="Move focus down"),
    Key([mod], "k", lazy.layout.up(), desc="Move focus up"),
    # Change window sizes (MonadTall)
    Key([mod, "shift"], "l", lazy.layout.grow()),
    Key([mod, "shift"], "h", lazy.layout.shrink()),
    # Key([mod, "shift"], "h", lazy.layout.grow_left(),
    #     desc="Grow window to the left"),
    # Key([mod, "shift"], "l", lazy.layout.grow_right(),
    #     desc="Grow window to the right"),
    # Toggle floating
    Key([mod, "shift"], "f", lazy.window.toggle_floating()),
    # Key([mod], "f", lazy.window.toggle_fullscreen()),
    # Move windows up or down in current stack
    Key([mod, "shift"], "j", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up(), desc="Move window up"),
    # Toggle between different layouts as defined below
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    Key([mod, "shift"], "Tab", lazy.prev_layout(), desc="Toggle between layouts"),
    # Switch focus of monitors
    Key([mod], "period", lazy.next_screen()),
    Key([mod], "comma", lazy.prev_screen()),
    Key([mod], "n", lazy.layout.normalize(), desc="Reset all window sizes"),
    # Key([mod], "space", lazy.layout.next(),
    #    desc="Move window focus to other window"),
    # Key([mod, "control"], "h", lazy.layout.shuffle_left(),
    #     desc="Move window to the left"),
    # Key([mod, "control"], "l", lazy.layout.shuffle_right(),
    #     desc="Move window to the right"),
    # Key([mod, "shift"], "j", lazy.layout.grow_down(), desc="Grow window down"),
    # Key([mod, "shift"], "k", lazy.layout.grow_up(), desc="Grow window up"),
    # Key(
    #     [mod, "shift"],
    #     "Return",
    #     lazy.layout.toggle_split(),
    #     desc="Toggle between split and unsplit sides of stack",
    # ),
    # Kill window
    Key([mod], "w", lazy.window.kill(), desc="Kill focused window"),
    # Restart Qtile
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    # C U S T O M
    Key([mod], "Return", lazy.spawn(terminal), desc="Launch terminal"),
    # Key([mod], "m", lazy.spawn("rofi -show drun"), desc="Spawn a command using a prompt widget"),
    Key(
        [mod],
        "m",
        lazy.spawn("sh -c ~/.config/rofi/launchers/type-1/launcher.sh"),
        desc="Spawn a command using a prompt widget",
    ),
    # Key([mod], "p", lazy.spawn(
    #    "sh -c ~/.config/rofi/scripts/power"), desc='powermenu'),
    # Key([mod], "t", lazy.spawn("sh -c ~/.config/rofi/scripts/themes"),
    #    desc='theme_switcher'),
    # ------------ Hardware Configs ------------
    # Volume
    Key(
        [],
        "XF86AudioRaiseVolume",
        lazy.spawn("pactl set-sink-volume 0 +5%"),
        desc="Volume Up",
    ),
    Key(
        [],
        "XF86AudioLowerVolume",
        lazy.spawn("pactl set-sink-volume 0 -5%"),
        desc="volume down",
    ),
    Key(
        [], "XF86AudioMute", lazy.spawn("pulsemixer --toggle-mute"), desc="Volume Mute"
    ),
    Key([], "XF86AudioPlay", lazy.spawn("playerctl play-pause"), desc="playerctl"),
    Key([], "XF86AudioPrev", lazy.spawn("playerctl previous"), desc="playerctl"),
    Key([], "XF86AudioNext", lazy.spawn("playerctl next"), desc="playerctl"),
    # Brightness
    Key(
        [],
        "XF86MonBrightnessUp",
        lazy.spawn("brightnessctl s 10%+"),
        desc="brightness UP",
    ),
    Key(
        [],
        "XF86MonBrightnessDown",
        lazy.spawn("brightnessctl s 10%-"),
        desc="brightness Down",
    ),
    # ------------ App Configs ------------
    # File Explorer
    Key([mod], "e", lazy.spawn("thunar"), desc="file manager"),
    # Clipboard
    Key([mod], "c", lazy.spawn("roficlip"), desc="clipboard"),
    # Screenshot
    Key([mod], "s", lazy.spawn("flameshot gui"), desc="Screenshot"),
    # Browser
    Key([mod], "b", lazy.spawn("zen-browser")),
    # Redshift
    Key([mod], "r", lazy.spawn("redshift -O 2400")),
    Key([mod, "shift"], "r", lazy.spawn("redshift -x")),
]


# █▀▀ █▀█ █▀█ █░█ █▀█ █▀
# █▄█ █▀▄ █▄█ █▄█ █▀▀ ▄█


def get_keyboard_layout():
    """Detecta el layout de teclado actual usando setxkbmap."""
    try:
        result = subprocess.run(["setxkbmap", "-query"], capture_output=True, text=True)

        keyboard_layout = "us"
        keyboard_variant = ""

        for line in result.stdout.split("\n"):
            if "layout" in line:
                keyboard_layout = line.split(":")[1].strip()
            if "variant" in line:
                keyboard_variant = line.split(":")[1].strip()

        return (
            f"{keyboard_layout}-{keyboard_variant}"
            if keyboard_variant
            else keyboard_layout
        )
    except Exception:
        return "us"


# Mapeos de teclas en cada layout
qwerty_keys = ["1", "2", "3", "4", "5", "6", "7", "8"]
dvorak_keys = [
    "ampersand",
    "bracketleft",
    "braceleft",
    "braceright",
    "parenleft",
    "equal",
    "asterisk",
    "parenright",
]

# Detectar si está en Dvorak programming
current_layout = get_keyboard_layout()
keys_mapping = dvorak_keys if "us-dvp" in current_layout else qwerty_keys

groups = [Group(f"{i + 1}", label="󰏃") for i in range(8)]

for i, key_name in zip(groups, keys_mapping):
    keys.extend(
        [
            Key(
                [mod],
                key_name,
                lazy.group[i.name].toscreen(),
                desc="Switch to group {}".format(i.name),
            ),
            Key(
                [mod, "shift"],
                key_name,
                lazy.window.togroup(i.name, switch_group=True),
                desc="Switch to & move focused window to group {}".format(i.name),
            ),
        ]
    )


# L A Y O U T S


layouts = [
    layout.MonadTall(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        margin=10,
        border_width=0,
    ),
    layout.Max(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        border_width=0,
    ),
    layout.MonadWide(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        margin=10,
        border_width=0,
    ),
    layout.Matrix(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        margin=[5, 10, 10, 10],
        border_width=0,
    ),
    layout.Bsp(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        margin=10,
        border_width=0,
    ),
    layout.Floating(
        border_focus="#1F1D2E",
        border_normal="#1F1D2E",
        margin=[5, 10, 10, 10],
        border_width=0,
    ),
    # Try more layouts by unleashing below layouts
    #  layout.Stack(num_stacks=2),
    #  layout.RatioTile(),
    #  layout.TreeTab(),
    #  layout.VerticalTile(),
    #  layout.Zoomy(),
    # layout.Tile(border_focus='#1F1D2E',
    #             border_normal='#1F1D2E',
    #             ),
    # layout.Columns(margin=[5, 10, 10, 10], border_focus='#1F1D2E',
    #                border_normal='#1F1D2E',
    #                border_width=0,
    #                ),
]


widget_defaults = dict(
    font="CaskaydiaCoveNerdFont-Bold",
    fontsize=12,
    padding=3,
)
extension_defaults = [widget_defaults.copy()]


def search():
    qtile.cmd_spawn("rofi -show drun")


def power():
    qtile.cmd_spawn("sh -c ~/.config/rofi/scripts/power")


# █▄▄ ▄▀█ █▀█
# █▄█ █▀█ █▀▄


screens = [
    Screen(
        # top=bar.Bar(
        #     [
        #         widget.Spacer(
        #             length=15,
        #             background="#232A2E",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/launch_Icon.png",
        #             margin=2,
        #             background="#232A2E",
        #             mouse_callbacks={"Button1": power},
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/6.png",
        #         ),
        #         widget.GroupBox(
        #             fontsize=24,
        #             borderwidth=3,
        #             highlight_method="block",
        #             active="#86918A",
        #             block_highlight_text_color="#D3C6AA",
        #             highlight_color="#4B427E",
        #             inactive="#232A2E",
        #             foreground="#4B427E",
        #             background="#343F44",
        #             this_current_screen_border="#343F44",
        #             this_screen_border="#343F44",
        #             other_current_screen_border="#343F44",
        #             other_screen_border="#343F44",
        #             urgent_border="#343F44",
        #             rounded=True,
        #             disable_drag=True,
        #         ),
        #         widget.Spacer(
        #             length=8,
        #             background="#343F44",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/1.png",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/layout.png", background="#343F44"
        #         ),
        #         widget.CurrentLayout(
        #             background="#343F44",
        #             foreground="#86918A",
        #             fmt="{}",
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/5.png",
        #         ),
        #         widget.Net(
        #             format=" {up}   {down} ",
        #             background="#232A2E",
        #             foreground="#86918A",
        #             font="JetBrains Mono Bold",
        #             prefix="k",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/4.png",
        #         ),
        #         widget.WindowName(
        #             background="#343F44",
        #             format="{name}",
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #             foreground="#86918A",
        #             empty_group_string="Desktop",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/3.png",
        #         ),
        #         widget.Systray(
        #             background="#232A2E",
        #             fontsize=2,
        #         ),
        #         widget.TextBox(
        #             text=" ",
        #             background="#232A2E",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/6.png",
        #             background="#343F44",
        #         ),
        #         # widget.Image(
        #         #     filename='~/.config/qtile/Assets/Drop1.png',
        #         # ),
        #         # widget.Net(
        #         #     format=' {up}   {down} ',
        #         #     background='#343F44',
        #         #     foreground='#86918A',
        #         #     font="JetBrains Mono Bold",
        #         #     prefix='k',
        #         # ),
        #         # widget.Image(
        #         #     filename='~/.config/qtile/Assets/2.png',
        #         # ),
        #         # widget.Spacer(
        #         #     length=8,
        #         #     background='#343F44',
        #         # ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/Misc/ram.png",
        #             background="#343F44",
        #         ),
        #         widget.Spacer(
        #             length=-7,
        #             background="#343F44",
        #         ),
        #         widget.Memory(
        #             background="#343F44",
        #             format="{MemUsed: .0f}{mm}",
        #             foreground="#86918A",
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #             update_interval=5,
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/2.png",
        #         ),
        #         # widget.Spacer(
        #         #     length=8,
        #         #     background='#343F44',
        #         # ),
        #         # widget.BatteryIcon(
        #         #     theme_path='~/.config/qtile/Assets/Battery/',
        #         #     background='#343F44',
        #         #     scale=1,
        #         # ),
        #         # widget.Battery(
        #         #     font="JetBrains Mono Bold",
        #         #     fontsize=13,
        #         #     background='#343F44',
        #         #     foreground='#86918A',
        #         #     format='{percent:2.0%}',
        #         # ),
        #         # widget.Image(
        #         #     filename='~/.config/qtile/Assets/2.png',
        #         # ),
        #         widget.Spacer(
        #             length=8,
        #             background="#343F44",
        #         ),
        #         # widget.Battery(format=' {percent:2.0%}',
        #         # font="JetBrains Mono ExtraBold",
        #         # fontsize=12,
        #         # padding=10,
        #         # background='#343F44',
        #         # ),
        #         # widget.Memory(format='﬙{MemUsed: .0f}{mm}',
        #         # font="JetBrains Mono Bold",
        #         # fontsize=12,
        #         # padding=10,
        #         # background='#4B4D66',
        #         # ),
        #         widget.Volume(
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #             theme_path="~/.config/qtile/Assets/Volume/",
        #             emoji=True,
        #             background="#343F44",
        #         ),
        #         widget.Spacer(
        #             length=-5,
        #             background="#343F44",
        #         ),
        #         widget.Volume(
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #             background="#343F44",
        #             foreground="#86918A",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/5.png",
        #             background="#343F44",
        #         ),
        #         widget.Image(
        #             filename="~/.config/qtile/Assets/Misc/clock.png",
        #             background="#232A2E",
        #             margin_y=6,
        #             margin_x=5,
        #         ),
        #         widget.Clock(
        #             format="%I:%M %p",
        #             background="#232A2E",
        #             foreground="#86918A",
        #             font="JetBrains Mono Bold",
        #             fontsize=13,
        #         ),
        #         widget.Spacer(
        #             length=18,
        #             background="#232A2E",
        #         ),
        #     ],
        #     30,
        #     border_color="#232A2E",
        #     border_width=[0, 0, 0, 0],
        #     margin=[6, 6, 6, 6],
        # ),
        top=bar.Gap(10),
    ),
]


# Drag floating layouts.
mouse = [
    Drag(
        [mod],
        "Button1",
        lazy.window.set_position_floating(),
        start=lazy.window.get_position(),
    ),
    Drag(
        [mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()
    ),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]


dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    border_focus="#1F1D2E",
    border_normal="#1F1D2E",
    border_width=0,
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
    ],
)


# stuff


@hook.subscribe.startup_once
def autostart():
    subprocess.call([os.path.expanduser(".config/qtile/autostart.sh")])


auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None

# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"


# E O F
