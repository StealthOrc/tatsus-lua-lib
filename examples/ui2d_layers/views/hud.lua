local UI = require("ui2d")

return UI.view("hud", {
    styles = {
        colors = {
            world = {0.025, 0.04, 0.065, 1},
        },
    },
    build = function()
        return UI.screen {
            background = "world",
            padding = 28,
            UI.column {
                anchor = "center",
                align = "center",
                gap = 12,
                UI.text {value = "UI in Motion", style = "title"},
                UI.text {
                    value = "Try me with a mouse or gamepad — click below or press accept.",
                    style = "body",
                },
            },
            UI.row {
                anchor = "bottom-center",
                gap = 12,
                UI.button {
                    id = "open-menu",
                    style = "motion",
                    label = "Open full menu",
                    action = "open_menu",
                },
                UI.button {
                    id = "open-lab",
                    style = "motion",
                    label = "Open component lab",
                    action = "open_lab",
                },
            },
        }
    end,
})
