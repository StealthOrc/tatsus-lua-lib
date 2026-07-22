local UI = require("ui2d")

return UI.view("binding-game-hud", {
    styles = {
        text = {
            hud_title = {size = 20, color = "text"},
            hud = {size = 13, color = "muted"},
        },
    },
    build = function(model)
        return UI.screen {
            padding = 26,
            UI.column {
                anchor = "top-left",
                gap = 3,
                UI.text {value = "COLOR RITE", style = "hud_title"},
                UI.text {
                    value = string.format(
                        "RITE %d / %d  ·  COMPLETED %02d",
                        model.round,
                        model.rounds,
                        model.completed
                    ),
                    style = "hud",
                },
            },
            UI.column {
                anchor = "top-right",
                align = "end",
                gap = 3,
                UI.text {value = model.pause_hint, style = "hud_title"},
                UI.text {value = model.device_label, style = "hud"},
                UI.text {
                    value = model.dash_hint,
                    style = "hud",
                    color = model.dash_color,
                },
            },
            UI.column {
                anchor = "bottom-left",
                gap = 3,
                UI.text {value = "CURRENT TINT", style = "label"},
                UI.text {
                    value = model.carried,
                    style = "title",
                    color = model.carried_color,
                },
            },
            UI.text {
                anchor = "bottom-center",
                value = "Collect the recipe in order. Return each tint to the central seal.",
                style = "small",
            },
        }
    end,
})
