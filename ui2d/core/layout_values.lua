local Units = require("ui2d.core.units")

local LayoutValues = {}

function LayoutValues.resolve_token(styles, value)
    local seen = {}
    while type(value) == "string" and value ~= "fill" and value ~= "content" do
        if seen[value] then error("cyclic stylesheet token: " .. value) end
        seen[value] = true
        local resolved = styles:get(value)
        if resolved == nil then break end
        value = resolved
    end
    return value
end

function LayoutValues.length(value, available, env, font_size)
    value = LayoutValues.resolve_token(env.styles, value)
    return Units.resolve(value, available, {
        scale = env.scale,
        font_size = font_size,
        root_font_size = env.styles.values.root_font_size * env.scale,
    })
end

function LayoutValues.dimension(value, available, content, env, font_size)
    value = LayoutValues.resolve_token(env.styles, value)
    if value == nil or value == "content" then return content end
    if value == "fill" then return available end
    return LayoutValues.length(value, available, env, font_size)
end

function LayoutValues.insets(value, available_w, available_h, env, font_size)
    value = LayoutValues.resolve_token(env.styles, value or 0)
    if type(value) ~= "table" or Units.is(value) then
        local horizontal = LayoutValues.length(value, available_w, env, font_size) or 0
        local vertical = LayoutValues.length(value, available_h, env, font_size) or 0
        return {left = horizontal, right = horizontal, top = vertical, bottom = vertical}
    end
    local x = value.x or value.horizontal or 0
    local y = value.y or value.vertical or 0
    return {
        left = LayoutValues.length(value.left or x, available_w, env, font_size) or 0,
        right = LayoutValues.length(value.right or x, available_w, env, font_size) or 0,
        top = LayoutValues.length(value.top or y, available_h, env, font_size) or 0,
        bottom = LayoutValues.length(value.bottom or y, available_h, env, font_size) or 0,
    }
end

function LayoutValues.overlay_style(style, node)
    for key in pairs(style) do
        if node[key] ~= nil then style[key] = node[key] end
    end
    return style
end

return LayoutValues
