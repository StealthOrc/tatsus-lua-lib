local Nodes = require("ui2d.core.nodes")

local Progress = {}

local function normalized(spec)
    if spec.indeterminate then return 1 end
    local minimum = tonumber(spec.minimum or spec.min) or 0
    local maximum = tonumber(spec.maximum or spec.max) or 1
    assert(maximum > minimum,
        "progress maximum must be greater than minimum")
    local value = tonumber(spec.value) or minimum
    return math.max(0, math.min(
        1,
        (value - minimum) / (maximum - minimum)
    ))
end

function Progress.new(spec)
    spec = spec or {}
    local progress = normalized(spec)
    local vertical = spec.direction == "vertical"
    local reverse = spec.reverse == true
    local fill_transform
    if spec.indeterminate then
        fill_transform = {
            scale_x = vertical and 1 or 0.35,
            scale_y = vertical and 0.35 or 1,
            origin_x = reverse and 1 or 0,
            origin_y = reverse and 0 or 1,
        }
    else
        fill_transform = {
            scale_x = vertical and 1 or progress,
            scale_y = vertical and progress or 1,
            origin_x = reverse and 1 or 0,
            origin_y = vertical and (reverse and 0 or 1) or 0,
        }
    end
    local fill = Nodes.panel {
        id = spec.id and spec.id .. "-fill" or nil,
        z = 0,
        anchor = vertical
            and (reverse and "top-left" or "bottom-left")
            or (reverse and "top-right" or "top-left"),
        width = "fill",
        height = "fill",
        radius = spec.fill_radius or spec.radius,
        background = spec.fill or spec.foreground,
        pointer = "pass",
        transform = fill_transform,
        transition = {
            transform = spec.transition
                or {duration = 0.18, ease = "out_cubic"},
        },
    }
    local children = {fill}
    if spec.content then
        children[#children + 1] = spec.content
    elseif spec.label ~= nil then
        children[#children + 1] = Nodes.text {
            z = 1,
            anchor = "center",
            value = spec.label,
            style = spec.text_style,
            color = spec.text_color,
        }
    end
    return Nodes.stack {
        id = spec.id,
        styles = spec.styles,
        width = spec.width or "fill",
        height = spec.height or 24,
        radius = spec.radius or 5,
        background = spec.background,
        border = spec.border,
        border_width = spec.border_width,
        overflow = "hidden",
        pointer = spec.pointer or "pass",
        children = children,
    }
end

return Progress
