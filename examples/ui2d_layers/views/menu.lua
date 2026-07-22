local UI = require("ui2d")

return UI.view("menu", {
    styles = {
        colors = {
            overlay = {0.035, 0.045, 0.075, 0.97},
        },
        buttons = {
            motion = {radius = 9},
        },
        text_fields = {
            menu_title = {
                background = {0.07, 0.08, 0.12, 1},
                foreground = "white",
                selection = "accent",
                caret = "accent",
                border_focused = "accent",
                min_width = 300,
                min_height = 42,
                padding_x = 12,
                padding_y = 9,
                radius = 8,
                text = "body",
            },
        },
    },
    build = function(model)
        return UI.screen {
            background = "overlay",
            UI.column {
                anchor = "center",
                align = "center",
                gap = 18,
                UI.text {value = model.title, style = "title"},
                UI.text {
                    value = "Nothing behind this view receives input.",
                    style = "body",
                },
                UI.text_field {
                    id = "menu-title",
                    style = "menu_title",
                    value = model.title,
                    placeholder = "Name this view",
                    changed = "rename_menu",
                    max_length = 32,
                },
                UI.button {
                    id = "toggle-drawer",
                    style = "motion",
                    label = model.drawer_open and "Close lower drawer" or "Open lower drawer",
                    action = "toggle_drawer",
                },
                UI.button {
                    id = "hold-open-drawer",
                    style = "motion",
                    label = "Hold to fully open drawer",
                    action = "open_drawer_fully",
                    hold = {duration = 1},
                    hold_indicator = {
                        direction = "right",
                        background = "white",
                        opacity = 0.32,
                    },
                },
                UI.button {
                    id = "close-menu",
                    style = "motion",
                    label = "Close menu",
                    action = "close_menu",
                },
            },
        }
    end,
})
