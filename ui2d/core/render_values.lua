local StyleSheet = require("ui2d.core.style_sheet")

local RenderValues = {}

function RenderValues.color(styles, value, fallback)
    local resolved = styles:color(value) or fallback or {1, 1, 1, 1}
    return {
        resolved[1] or 0,
        resolved[2] or 0,
        resolved[3] or 0,
        resolved[4] == nil and 1 or resolved[4],
    }
end

function RenderValues.shifted(source, amount)
    return {
        math.max(0, math.min(1, source[1] + amount)),
        math.max(0, math.min(1, source[2] + amount)),
        math.max(0, math.min(1, source[3] + amount)),
        source[4],
    }
end

function RenderValues.set_color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], value[4] * (alpha or 1))
end

function RenderValues.interaction_style(item, name)
    local states = StyleSheet.copy(item.style and item.style.states or {})
    StyleSheet.merge(states, item.node.states or {})
    return StyleSheet.interaction_state(states, name) or {}
end

return RenderValues
