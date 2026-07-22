local UI = require("ui2d")

return UI.view("menu", function(model)
    return UI.screen {
        background = "overlay",
        UI.column {
            anchor = "center",
            align = "center",
            gap = 18,
            UI.text {value = "Blocking View Layer", style = "title"},
            UI.text {value = "Nothing behind this view receives input.", style = "body"},
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
end)
