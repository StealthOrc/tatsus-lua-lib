local UI = require("ui2d")

return UI.view("lab-modal", function()
    return UI.modal {
        id = "lab-modal",
        initial = "confirm-lab-modal",
        width = 440,
        veil = {0.015, 0.02, 0.035, 0.86},
        background = {0.07, 0.085, 0.13, 1},
        border = "accent",
        border_width = 2,
        content = UI.column {
            gap = 10,
            UI.text {
                value = "Blocking modal layer",
                style = "title",
            },
            UI.text {
                value = "Selection stays inside this layer and lower views cannot receive pointer, keyboard, or controller input.",
                width = "fill",
                wrap = true,
                style = "body",
            },
        },
        actions = {
            {
                id = "cancel-lab-modal",
                label = "Cancel",
                style = "motion",
                action = "close_lab_modal",
            },
            {
                id = "confirm-lab-modal",
                label = "Confirm",
                style = "motion",
                action = "close_lab_modal",
            },
        },
    }
end)
