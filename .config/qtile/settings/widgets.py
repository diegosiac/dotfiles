from libqtile import widget
from .theme import colors

# Get the icons at https://www.nerdfonts.com/cheat-sheet (you need a Nerd Font)


def base(fg='text', bg='dark'):
    return {
        'foreground': colors[fg],
        'background': colors[bg]
    }


def separator():
    return widget.Sep(**base("active", "dark"), linewidth=1, padding=5)


def icon(fg='text', bg='dark', fontsize=16, text="?"):
    return widget.TextBox(
        **base(fg, bg),
        fontsize=fontsize,
        text=text,
        padding=3
    )


def rounded_left(fg="light"):
    return widget.TextBox(
        **base(fg, "dark"),
        text=" ",  # Icon: nf-oct-triangle_left
        fontsize=31,
        padding=-8
    )


def rounded_right(fg="light"):
    return widget.TextBox(
        **base(fg, "dark"),
        text=" ",  # Icon: nf-mdi-arrow-right
        fontsize=31,
        padding=-8
    )


def workspaces():
    return [
        widget.GroupBox(
            **base(fg='light'),
            font='UbuntuMono Nerd Font',
            fontsize=19,
            margin_y=3,
            margin_x=0,
            padding_y=8,
            padding_x=5,
            borderwidth=1,
            active=colors['active'],
            inactive=colors['inactive'],
            rounded=True,
            highlight_method='block',
            urgent_alert_method='block',
            urgent_border=colors['urgent'],
            this_current_screen_border=colors['focus'],
            this_screen_border=colors['grey'],
            other_current_screen_border=colors['dark'],
            other_screen_border=colors['dark'],
            disable_drag=True
        ),
        widget.WindowName(**base(fg='focus'), fontsize=14, padding=5),
    ]


primary_widgets = [
    *workspaces(),

    rounded_left('color4'),

    icon(bg="color4", text=' '),

    widget.CheckUpdates(
        background=colors['color4'],
        colour_have_updates=colors['text'],
        colour_no_updates=colors['text'],
        no_update_string='0',
        display_format='{updates}',
        update_interval=1800,
        custom_command='checkupdates',
    ),

    rounded_right('color4'),

    separator(),

    rounded_left('color3'),

    icon(bg="color3", text=' '),  # Icon: nf-fa-feed

    widget.Net(**base(bg='color3'), interface='enp3s0'),

    rounded_right('color3'),

    separator(),

    rounded_left('color2'),

    widget.CurrentLayoutIcon(**base(fg='dark', bg='color2'), scale=0.65),

    widget.CurrentLayout(**base(bg='color2'), padding=5),

    rounded_right('color2'),

    separator(),

    rounded_left('color1'),

    icon(bg="color1", fontsize=17, text='󰥔 '),  # Icon: nf-mdi-calendar_clock

    widget.Clock(**base(bg='color1'), format='%H:%M - %d/%m/%Y'),

    rounded_right('color1'),

    separator(),

    rounded_left('dark'),

    widget.Systray(background=colors['dark'], padding=5),

    rounded_right('dark'),
]

secondary_widgets = [
    *workspaces(),

    rounded_left('color1'),

    widget.CurrentLayoutIcon(**base(fg='dark', bg='color1'), scale=0.65),

    widget.CurrentLayout(**base(bg='color1'), padding=5),

    rounded_right('color1'),

    separator(),

    rounded_left('color2'),

    widget.Clock(**base(bg='color2'), format='%d/%m/%Y - %H:%M '),

    rounded_right('color2'),
]

widget_defaults = {
    'font': 'UbuntuMono Nerd Font Bold',
    'fontsize': 14,
    'padding': 1,
}
extension_defaults = widget_defaults.copy()
