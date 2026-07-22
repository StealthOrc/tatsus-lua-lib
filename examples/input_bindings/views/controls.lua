local UI = require("ui2d")

local function divider()
    return UI.panel {width = "fill", height = 1, pointer = "pass", background = "line"}
end

local function binding_row(row, enabled)
    return UI.button {
        id = "binding-" .. row.action,
        style = "binding",
        width = "fill",
        enabled = enabled,
        action = {type = "rebind", input_action = row.action, scheme = row.scheme},
        content = UI.row {
            width = "fill",
            align = "center",
            UI.text {value = row.label, style = "body"},
            UI.spacer {flex = 1},
            UI.text {value = row.binding, style = "binding"},
        },
    }
end

return UI.view("binding-game-controls", function(model)
    local contents = {
        UI.row {
            width = "fill",
            align = "center",
            UI.column {
                gap = 2,
                UI.text {value = "COLOR RITE", style = "label", color = "accent"},
                UI.text {value = "Controls", style = "display"},
            },
            UI.spacer {flex = 1},
            UI.column {
                align = "end",
                gap = 2,
                UI.text {value = "ACTIVE INPUT", style = "label"},
                UI.text {value = model.device_label, style = "body", color = "accent"},
            },
        },
        divider(),
    }

    if model.scheme == "gamepad" then
        contents[#contents + 1] = UI.column {
            width = "fill",
            gap = 7,
            UI.text {value = "GAMEPAD MOVEMENT SHAPE", style = "label"},
            UI.segmented_control {
                id = "gamepad-movement-shape",
                value = model.gamepad_mode,
                options = {
                    {value = "stick", label = "STICK"},
                    {value = "axes", label = "AXES"},
                    {value = "directions", label = "DIRECTIONS"},
                },
                changed = "set_gamepad_mode",
                button_style = "segment",
                selected_style = "segment_active",
                background = "panel_soft",
                indicator_background = "segment_fill",
                radius = 8,
            },
        }
        contents[#contents + 1] = divider()
    end

    contents[#contents + 1] = UI.row {
        width = "fill",
        UI.text {value = "ACTION", style = "label"},
        UI.spacer {flex = 1},
        UI.text {value = "BINDING", style = "label"},
    }
    for _, row in ipairs(model.rows) do
        contents[#contents + 1] = binding_row(row, model.capture == nil)
    end
    contents[#contents + 1] = UI.text {
        value = model.capture or "Select a row to replace its binding.",
        style = model.capture and "binding" or "small",
    }
    contents[#contents + 1] = divider()
    contents[#contents + 1] = UI.row {
        width = "fill",
        align = "center",
        UI.text {value = model.footer_hint, style = "small"},
        UI.spacer {flex = 1},
        UI.button {id = "resume-game", style = "resume", label = "Resume", action = "resume"},
    }

    return UI.screen {
        background = "veil",
        UI.panel {
            id = "controls-panel",
            anchor = "center",
            width = UI.percent(0.76),
            padding = 26,
            radius = 14,
            background = "panel",
            border = "line",
            border_width = 1,
            UI.column {width = "fill", gap = 11, children = contents},
        },
    }
end)
