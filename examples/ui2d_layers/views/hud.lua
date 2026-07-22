local UI = require("ui2d")

return UI.view("hud", function()
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
        UI.button {
            id = "open-menu",
            anchor = "bottom-center",
            style = "motion",
            label = "Open full menu",
            action = "open_menu",
        },
    }
end)
