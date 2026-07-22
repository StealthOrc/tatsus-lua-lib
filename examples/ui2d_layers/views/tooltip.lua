local UI = require("ui2d")

local tooltip_width = 330
local tooltip_height = 158
local tooltip_margin = 24
local tooltip_gap = 12

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function tooltip_position(model)
    local viewport_w = model.viewport_w or 960
    local viewport_h = model.viewport_h or 640
    if model.mode == "pointer" then
        local x = clamp(
            (model.pointer_x or 0) + tooltip_gap,
            tooltip_margin,
            viewport_w - tooltip_width - tooltip_margin
        )
        local below = (model.pointer_y or 0) + tooltip_gap
        local y = below + tooltip_height <= viewport_h - tooltip_margin
            and below or (model.pointer_y or 0) - tooltip_height - tooltip_gap
        return x, clamp(y, tooltip_margin, viewport_h - tooltip_height - tooltip_margin), "pointer"
    elseif model.mode == "button" and model.target then
        local target = model.target
        local x = target.x + (target.w - tooltip_width) / 2
        local above = target.y - tooltip_height - tooltip_gap
        local side = above >= tooltip_margin and "above button" or "below button"
        local y = side == "above button" and above or target.y + target.h + tooltip_gap
        return clamp(x, tooltip_margin, viewport_w - tooltip_width - tooltip_margin),
            clamp(y, tooltip_margin, viewport_h - tooltip_height - tooltip_margin), side
    end
    return viewport_w - tooltip_width - tooltip_margin, tooltip_margin, "top-right"
end

return UI.view("tooltip", function(model)
    local x, y, placement = tooltip_position(model)
    return UI.screen {
        UI.panel {
            id = "tooltip-panel",
            anchor = "top-left",
            width = tooltip_width,
            height = tooltip_height,
            padding = 18,
            radius = 8,
            pointer = model.mode == "pointer" and "pass" or nil,
            background = "tooltip",
            border = "accent",
            border_width = 2,
            transform = {translate_x = UI.px(x), translate_y = UI.px(y)},
            transition = {
                transform = {
                    duration = model.animate_position or (model.mode ~= "pointer" and 0.18 or 0),
                    ease = "out_cubic",
                },
            },
            UI.column {
                gap = 8,
                UI.text {value = "Tooltip · " .. placement, style = "title"},
                UI.text {value = "Click to cycle anchor policies.", style = "body"},
                UI.text {
                    value = model.mode == "pointer" and "Pointer-follow mode passes input."
                        or "Inside consumes pointer input.",
                    style = "body",
                },
                UI.text {value = "Outside remains pass-through.", style = "body"},
            },
        },
    }
end)
