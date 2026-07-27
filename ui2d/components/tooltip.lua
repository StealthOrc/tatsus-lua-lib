local Nodes = require("ui2d.core.nodes")

local Tooltip = {}

function Tooltip.new(spec)
    spec = spec or {}
    assert(spec.target ~= nil, "tooltip requires a target")
    local content = spec.content or spec.children
    if content and not content.kind and #content > 1 then
        content = Nodes.column {
            gap = spec.gap or 8,
            children = content,
        }
    end
    return Nodes.panel {
        id = spec.id,
        styles = spec.styles,
        width = spec.width or "content",
        height = spec.height or "content",
        max_width = spec.max_width,
        padding = spec.padding,
        gap = spec.gap,
        radius = spec.radius,
        background = spec.background,
        border = spec.border,
        border_width = spec.border_width,
        pointer = spec.pointer or "pass",
        tooltip = {
            target = spec.target,
            placement = spec.placement or "auto",
            collision = spec.collision or "flip",
            gap = spec.anchor_gap or 10,
            margin = spec.margin or 12,
            place = spec.place,
        },
        children = content and (content.kind and {content} or content) or {},
    }
end

return Tooltip
