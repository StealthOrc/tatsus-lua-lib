local Layout = require("ui2d.core.layout")
local RenderValues = require("ui2d.core.render_values")
local Button = require("ui2d.components.button")
local TextField = require("ui2d.components.text_field")

local Renderer = {}
Renderer.__index = Renderer

local color = RenderValues.color
local set_color = RenderValues.set_color

local function apply_transform(spec)
    love.graphics.translate(spec.translate_x, spec.translate_y)
    love.graphics.translate(spec.origin_x, spec.origin_y)
    love.graphics.rotate(spec.rotation)
    love.graphics.scale(spec.scale_x, spec.scale_y)
    love.graphics.translate(-spec.origin_x, -spec.origin_y)
end

local function primary_surface(item)
    if item.kind == "text" or item.kind == "icon" then return "content" end
    return "background"
end

local function declared_surface(item, surface)
    local node_surfaces = item.node.shaders
    if node_surfaces and node_surfaces[surface] ~= nil then return node_surfaces[surface] end
    local style_surfaces = item.style and item.style.shaders
    if style_surfaces and style_surfaces[surface] ~= nil then return style_surfaces[surface] end
    if primary_surface(item) == surface and item.node.shader ~= nil then return item.node.shader end
    if primary_surface(item) == surface and item.style and item.style.shader ~= nil then return item.style.shader end
    return nil
end

function Renderer.new(styles, icons, shaders)
    return setmetatable({styles = styles, icons = icons, shaders = shaders}, Renderer)
end

function Renderer:with_surface(spec, surface, item, context, layout, entry, alpha, draw)
    return self.shaders:with(spec, {
        surface = surface,
        item = item,
        context = context,
        layout = layout,
        entry = entry,
        alpha = alpha,
    }, draw)
end

function Renderer:radius(item, scale)
    local value = item.node.radius or (item.style and item.style.radius) or 0
    return Layout.resolve_length(value, math.min(item.rect.w, item.rect.h), {
        styles = item.styles or self.styles,
        scale = scale,
    }) or 0
end

function Renderer:border_width(item, scale)
    local value = item.node.border_width or (item.style and item.style.border_width) or 1
    return Layout.resolve_length(value, item.rect.w, {
        styles = item.styles or self.styles,
        scale = scale,
    }) or 1
end

function Renderer:draw_border(item, value, radius, scale, alpha, shader, environment)
    if not value then return end
    local styles = item.styles or self.styles
    local width = self:border_width(item, scale)
    self:with_surface(shader, "border", item, environment.context, environment.layout,
        environment.entry, alpha, function()
            love.graphics.setLineWidth(math.max(1, width))
            set_color(color(styles, value), alpha)
            love.graphics.rectangle("line", item.rect.x + width / 2, item.rect.y + width / 2,
                math.max(0, item.rect.w - width), math.max(0, item.rect.h - width), radius, radius)
        end)
end

function Renderer:container(item, scale, alpha, surfaces, environment)
    local styles = item.styles or self.styles
    local radius = self:radius(item, scale)
    if item.node.background then
        self:with_surface(surfaces.background, "background", item, environment.context,
            environment.layout, environment.entry, alpha, function()
                set_color(color(styles, item.node.background), alpha)
                love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
            end)
    end
    self:draw_border(item, item.node.border, radius, scale, alpha, surfaces.border, environment)
end

local function draw_item(self, item, context, layout, entry, inherited_alpha, inherited_content_shader)
    love.graphics.push()
    apply_transform(item.visual_transform)
    local alpha = inherited_alpha * item.visual_opacity
    local content_shader = declared_surface(item, "content") or inherited_content_shader
    local surfaces = {
        background = declared_surface(item, "background"),
        border = declared_surface(item, "border"),
        content = content_shader,
    }
    local state = {
        hovered = context:is_hovered(entry, item.node.id),
        selected = context:is_selected(entry, item.node.id),
        pressed = context:is_pressed(entry, item.node.id),
        focused = context:is_focused(entry, item.node.id),
        holding = context:is_holding(entry, item.node.id),
        hold_progress = context:hold_progress(item.node.id, entry.key),
    }
    item.hold_progress = state.hold_progress
    local environment = {context = context, layout = layout, entry = entry}
    if item.kind == "screen" or item.kind == "panel" or item.kind == "row"
        or item.kind == "column" or item.kind == "stack"
    then
        self:container(item, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "button" then
        Button.draw(self, item, state, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "text_field" then
        TextField.draw(self, item, state,
            layout.scale, context.time, alpha, surfaces, environment)
    elseif item.kind == "text" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            love.graphics.setFont(item.font)
            set_color(color(item.styles or self.styles,
                item.node.color or item.text_style.color), alpha)
            local x = item.rect.x
            if item.node.align == "center" then x = item.rect.x + (item.rect.w - item.font:getWidth(item.text)) / 2
            elseif item.node.align == "right" then x = item.rect.x + item.rect.w - item.font:getWidth(item.text) end
            love.graphics.print(item.text, math.floor(x + 0.5), math.floor(item.rect.y + 0.5))
        end)
    elseif item.kind == "icon" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            local tint = item.node.tint and color(item.styles or self.styles, item.node.tint) or nil
            self.icons:draw(item.node.name, item.rect.x, item.rect.y, item.rect.w, item.rect.h,
                tint, (item.node.alpha or 1) * alpha)
        end)
    end
    for _, child in ipairs(item.children or {}) do
        draw_item(self, child, context, layout, entry, alpha, content_shader)
    end
    love.graphics.pop()
end

function Renderer:draw(layout, context, entry)
    if not layout then return end
    love.graphics.push("all")
    love.graphics.origin()
    if layout.layer_visual_transform then apply_transform(layout.layer_visual_transform) end
    draw_item(self, layout.root, context, layout, entry, layout.layer_opacity or 1, nil)
    love.graphics.pop()
end

return Renderer
