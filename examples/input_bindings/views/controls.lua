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

local styles = {
    colors = {
        veil = {0.012, 0.016, 0.025, 0.92},
        panel = {0.045, 0.057, 0.082, 0.985},
        panel_soft = {0.075, 0.092, 0.128, 0.94},
        line = {0.24, 0.34, 0.46, 0.42},
        accent_soft = {0.16, 0.90, 1.00, 0.14},
        segment_fill = {0.075, 0.18, 0.22, 1},
    },
    buttons = {
        binding = {
            background = "panel_soft",
            foreground = "text",
            min_height = 48,
            padding_x = 16,
            padding_y = 10,
            radius = 7,
            text = "body",
            transform = {translate_x = 0, scale = 1},
            states = {
                highlighted = {
                    background = "accent_soft",
                    border = "accent",
                    transform = {translate_x = 5, scale = 1},
                },
                hovered = "highlighted",
                selected = "highlighted",
                pressed = {
                    background = "accent_soft",
                    transform = {translate_x = 2, scale = 0.99},
                },
            },
            transition = {transform = {duration = 0.13, ease = "out_cubic"}},
        },
        resume = {
            background = "accent",
            foreground = "ink",
            min_height = 44,
            padding_x = 20,
            padding_y = 9,
            radius = 7,
            text = "body",
            transform = {scale = 1},
            states = {
                hovered = {transform = {scale = 1.035}},
                selected = {transform = {scale = 1.035}},
                pressed = {transform = {scale = 0.97}},
            },
            transition = {transform = {duration = 0.12, ease = "out_cubic"}},
        },
        segment = {
            background = "transparent",
            foreground = "muted",
            min_height = 40,
            padding_x = 12,
            padding_y = 8,
            radius = 5,
            text = "small",
            states = {
                hovered = {foreground = "text"},
                selected = {foreground = "text", focus = "accent"},
                pressed = {transform = {scale = 0.97}},
            },
        },
        segment_active = {
            background = "transparent",
            foreground = "accent",
            min_height = 40,
            padding_x = 12,
            padding_y = 8,
            radius = 5,
            text = "small",
            states = {
                hovered = {foreground = "text"},
                selected = {foreground = "accent", focus = "accent"},
                pressed = {transform = {scale = 0.97}},
            },
        },
    },
}

return UI.view("binding-game-controls", {
    styles = styles,
    build = function(model)
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
            UI.button {
                id = "resume-game",
                style = "resume",
                label = "Resume",
                action = "resume",
            },
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
    end,
})
