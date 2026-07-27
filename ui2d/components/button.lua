local Nodes = require("ui2d.core.nodes")
local LayoutValues = require("ui2d.core.layout_values")
local RenderValues = require("ui2d.core.render_values")

local Button = {}
local DEFAULT_FOCUS_ALPHA = 0.7

Nodes.register("button")

function Button.new(spec)
    return Nodes.construct("button", spec)
end

local function shorthand_content(node, style, env)
    if node.content then return node.content end
    if #(node.children or {}) > 0 then
        return Nodes.row {gap = style.gap, align = "center", children = node.children}
    end

    local children = {}
    local text_style = node.text_style or style.text
    local resolved_text = env.fonts:text_style(text_style)
    if node.icon then
        children[#children + 1] = Nodes.icon {
            name = node.icon,
            size = node.icon_size or style.icon_size or resolved_text.size * 1.2,
            tint = node.icon_tint or style.foreground,
        }
    end
    if node.label ~= nil then
        children[#children + 1] = Nodes.text {
            value = node.label,
            style = text_style,
            color = node.foreground or style.foreground,
        }
    end
    return Nodes.row {gap = node.gap or style.gap, align = "center", children = children}
end

function Button.measure(node, available_w, available_h, env, measure)
    assert(type(node.id) == "string" and node.id ~= "", "button requires a non-empty id")
    local style = LayoutValues.overlay_style(env.styles:button_style(node.style), node)
    local padding = {
        left = LayoutValues.length(style.padding_x or 0, available_w, env),
        right = LayoutValues.length(style.padding_x or 0, available_w, env),
        top = LayoutValues.length(style.padding_y or 0, available_h, env),
        bottom = LayoutValues.length(style.padding_y or 0, available_h, env),
    }
    local inner_w = math.max(0, available_w - padding.left - padding.right)
    local inner_h = math.max(0, available_h - padding.top - padding.bottom)
    local content = measure(shorthand_content(node, style, env), inner_w, inner_h, env)
    local content_w = content.w + padding.left + padding.right
    local content_h = content.h + padding.top + padding.bottom
    local min_w = LayoutValues.length(style.min_width or 0, available_w, env) or 0
    local min_h = LayoutValues.length(style.min_height or 0, available_h, env) or 0
    return {
        kind = "button",
        node = node,
        style = style,
        children = {content},
        padding = padding,
        enabled = node.enabled ~= false,
        interactive = true,
        w = math.max(min_w,
            LayoutValues.dimension(node.width, available_w, content_w, env)),
        h = math.max(min_h,
            LayoutValues.dimension(node.height, available_h, content_h, env)),
    }
end

function Button.draw(renderer, item, state, scale, alpha, surfaces, environment)
    local styles = item.styles or renderer.styles
    local style = item.style
    local base = RenderValues.color(styles, style.background)
    local interaction = {}
    if not item.enabled then
        interaction = RenderValues.interaction_style(item, "disabled")
        base = RenderValues.color(styles, interaction.background or style.background_disabled,
            {base[1], base[2], base[3], base[4] * 0.45})
    elseif state.pressed then
        interaction = RenderValues.interaction_style(item, "pressed")
        base = RenderValues.color(styles, interaction.background or style.background_pressed,
            RenderValues.shifted(base, -0.08))
    elseif state.hovered then
        interaction = RenderValues.interaction_style(item, "hovered")
        base = RenderValues.color(styles, interaction.background or style.background_hovered,
            RenderValues.shifted(base, 0.07))
    elseif state.selected then
        interaction = RenderValues.interaction_style(item, "selected")
        base = RenderValues.color(styles,
            interaction.background or style.background_selected or style.background_hovered,
            RenderValues.shifted(base, 0.07))
    end

    local radius = renderer:radius(item, scale)
    renderer:with_surface(surfaces.background, "background", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            RenderValues.set_color(base, alpha)
            love.graphics.rectangle("fill",
                item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
        end)

    local indicator = item.node.hold_indicator
    if indicator == nil then indicator = style.hold_indicator end
    if indicator and state.hold_progress > 0 then
        if indicator == true then indicator = {} end
        local direction = indicator.direction or "right"
        local x, y, width, height = item.rect.x, item.rect.y, item.rect.w, item.rect.h
        if direction == "left" then
            width = width * state.hold_progress
            x = item.rect.x + item.rect.w - width
        elseif direction == "up" then
            height = height * state.hold_progress
            y = item.rect.y + item.rect.h - height
        elseif direction == "down" then
            height = height * state.hold_progress
        else
            width = width * state.hold_progress
        end
        local fill = RenderValues.color(styles,
            indicator.background or indicator.color or style.foreground)
        local fill_alpha = indicator.opacity == nil and 0.28 or indicator.opacity
        renderer:with_surface(surfaces.background, "background", item, environment.context,
            environment.layout, environment.entry, alpha, function()
                RenderValues.set_color(fill, alpha * fill_alpha)
                love.graphics.rectangle("fill", x, y, width, height,
                    math.min(radius, width / 2), math.min(radius, height / 2))
            end)
    end

    renderer:draw_border(item, interaction.border or style.border,
        radius, scale, alpha, surfaces.border, environment)

    if state.focused or state.selected then
        local show_ring = item.node.focus_ring
        if show_ring == nil then show_ring = style.focus_ring end
        local focus_value = interaction.focus
        if focus_value == nil then focus_value = style.focus end
        if focus_value == nil then focus_value = style.foreground end
        -- Keep focus=false as a compatibility alias for hiding the visual ring.
        if show_ring ~= false and focus_value ~= false then
            local focus = RenderValues.color(styles, focus_value)
            local focus_alpha =
                (focus[4] == nil and 1 or focus[4])
                    * DEFAULT_FOCUS_ALPHA
            local inset = math.max(2, 3 * scale)
            renderer:with_surface(surfaces.border, "border", item, environment.context,
                environment.layout, environment.entry, alpha, function()
                    RenderValues.set_color(
                        {focus[1], focus[2], focus[3], focus_alpha},
                        alpha
                    )
                    love.graphics.setLineWidth(math.max(1, scale))
                    love.graphics.rectangle("line", item.rect.x + inset, item.rect.y + inset,
                        item.rect.w - inset * 2, item.rect.h - inset * 2,
                        math.max(0, radius - inset), math.max(0, radius - inset))
                end)
        end
    end
end

return Button
