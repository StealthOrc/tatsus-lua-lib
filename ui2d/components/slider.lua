local Nodes = require("ui2d.core.nodes")
local LayoutValues = require("ui2d.core.layout_values")
local RenderValues = require("ui2d.core.render_values")
local StyleSheet = require("ui2d.core.style_sheet")

local Slider = {}

Nodes.register("slider")

local function limits(node)
    local minimum = tonumber(node.minimum or node.min) or 0
    local maximum = tonumber(node.maximum or node.max) or 1
    assert(maximum > minimum, "slider maximum must be greater than minimum")
    return minimum, maximum
end

function Slider.value(node)
    local minimum, maximum = limits(node)
    return math.max(minimum, math.min(
        maximum,
        tonumber(node.value) or minimum
    ))
end

function Slider.normalized(node)
    local minimum, maximum = limits(node)
    return (Slider.value(node) - minimum) / (maximum - minimum)
end

function Slider.snap(node, value)
    local minimum, maximum = limits(node)
    local step = tonumber(node.step) or 0
    value = math.max(minimum, math.min(maximum, value))
    if step > 0 then
        value = minimum
            + math.floor((value - minimum) / step + 0.5) * step
        value = math.max(minimum, math.min(maximum, value))
    end
    return value
end

function Slider.changed_action(node, value)
    local action = node.changed or node.action
    local result
    if type(action) == "string" then
        result = {type = action}
    elseif type(action) == "table" then
        result = StyleSheet.copy(action)
    else
        return nil
    end
    result.control = result.control or node.id
    result.value = Slider.snap(node, value)
    return result
end

function Slider.value_at(item, x, y)
    local node = item.node
    local minimum, maximum = limits(node)
    local vertical = node.direction == "vertical"
    local ratio
    if vertical then
        ratio = 1 - (y - item.rect.y) / math.max(1, item.rect.h)
    else
        ratio = (x - item.rect.x) / math.max(1, item.rect.w)
    end
    ratio = math.max(0, math.min(1, ratio))
    return Slider.snap(node, minimum + (maximum - minimum) * ratio)
end

function Slider.adjusted_value(node, direction)
    local vertical = node.direction == "vertical"
    local delta
    if vertical and direction == "up"
        or not vertical and direction == "right" then
        delta = 1
    elseif vertical and direction == "down"
        or not vertical and direction == "left" then
        delta = -1
    else
        return nil
    end
    local minimum, maximum = limits(node)
    local step = tonumber(node.step) or (maximum - minimum) / 20
    return Slider.snap(node, Slider.value(node) + delta * step)
end

function Slider.new(spec)
    spec = spec or {}
    return Nodes.construct("slider", spec)
end

function Slider.measure(node, available_w, available_h, env)
    assert(type(node.id) == "string" and node.id ~= "",
        "slider requires a non-empty id")
    local style = LayoutValues.overlay_style(
        env.styles:slider_style(node.style),
        node
    )
    local vertical = node.direction == "vertical"
    local default_width = vertical and 34 or 240
    local default_height = vertical and 180 or 34
    return {
        kind = "slider",
        node = node,
        style = style,
        children = {},
        enabled = node.enabled ~= false,
        interactive = true,
        w = LayoutValues.dimension(
            node.width,
            available_w,
            default_width * env.scale,
            env
        ),
        h = LayoutValues.dimension(
            node.height,
            available_h,
            default_height * env.scale,
            env
        ),
    }
end

function Slider.draw(renderer, item, state, scale, alpha, surfaces, environment)
    local node = item.node
    local style = item.style
    local styles = item.styles or renderer.styles
    local vertical = node.direction == "vertical"
    local progress = Slider.normalized(node)
    local thickness = LayoutValues.length(
        style.track_thickness or 6,
        vertical and item.rect.w or item.rect.h,
        item.env
    ) or 6
    local thumb_size = LayoutValues.length(
        style.thumb_size or 18,
        vertical and item.rect.w or item.rect.h,
        item.env
    ) or 18
    local track = vertical and {
        x = item.rect.x + (item.rect.w - thickness) / 2,
        y = item.rect.y,
        w = thickness,
        h = item.rect.h,
    } or {
        x = item.rect.x,
        y = item.rect.y + (item.rect.h - thickness) / 2,
        w = item.rect.w,
        h = thickness,
    }
    local fill = {
        x = track.x,
        y = vertical
            and track.y + track.h * (1 - progress)
            or track.y,
        w = vertical and track.w or track.w * progress,
        h = vertical and track.h * progress or track.h,
    }
    local thumb_x = vertical
        and item.rect.x + item.rect.w / 2
        or item.rect.x + item.rect.w * progress
    local thumb_y = vertical
        and item.rect.y + item.rect.h * (1 - progress)
        or item.rect.y + item.rect.h / 2
    local dim = item.enabled and 1 or 0.45
    renderer:with_surface(
        surfaces.background,
        "background",
        item,
        environment.context,
        environment.layout,
        environment.entry,
        alpha,
        function()
            RenderValues.set_color(
                RenderValues.color(styles, style.track),
                alpha * dim
            )
            love.graphics.rectangle(
                "fill",
                track.x,
                track.y,
                track.w,
                track.h,
                thickness / 2,
                thickness / 2
            )
            RenderValues.set_color(
                RenderValues.color(styles, style.fill),
                alpha * dim
            )
            love.graphics.rectangle(
                "fill",
                fill.x,
                fill.y,
                fill.w,
                fill.h,
                thickness / 2,
                thickness / 2
            )
            RenderValues.set_color(
                RenderValues.color(
                    styles,
                    state.pressed and (style.thumb_pressed or style.thumb)
                        or state.selected and (style.thumb_selected or style.thumb)
                        or style.thumb
                ),
                alpha * dim
            )
            love.graphics.circle(
                "fill",
                thumb_x,
                thumb_y,
                thumb_size / 2
            )
        end
    )
end

return Slider
