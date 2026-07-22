local Layout = require("ui2d.layout")

local Renderer = {}
Renderer.__index = Renderer

local function color(styles, value, fallback)
    local resolved = styles:color(value) or fallback or {1, 1, 1, 1}
    return {resolved[1] or 0, resolved[2] or 0, resolved[3] or 0, resolved[4] == nil and 1 or resolved[4]}
end

local function shifted(source, amount)
    return {
        math.max(0, math.min(1, source[1] + amount)),
        math.max(0, math.min(1, source[2] + amount)),
        math.max(0, math.min(1, source[3] + amount)),
        source[4],
    }
end

local function set_color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], value[4] * (alpha or 1))
end

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
        styles = self.styles,
        scale = scale,
    }) or 0
end

function Renderer:border_width(item, scale)
    local value = item.node.border_width or (item.style and item.style.border_width) or 1
    return Layout.resolve_length(value, item.rect.w, {
        styles = self.styles,
        scale = scale,
    }) or 1
end

function Renderer:draw_border(item, value, radius, scale, alpha, shader, environment)
    if not value then return end
    local width = self:border_width(item, scale)
    self:with_surface(shader, "border", item, environment.context, environment.layout,
        environment.entry, alpha, function()
            love.graphics.setLineWidth(math.max(1, width))
            set_color(color(self.styles, value), alpha)
            love.graphics.rectangle("line", item.rect.x + width / 2, item.rect.y + width / 2,
                math.max(0, item.rect.w - width), math.max(0, item.rect.h - width), radius, radius)
        end)
end

function Renderer:container(item, scale, alpha, surfaces, environment)
    local radius = self:radius(item, scale)
    if item.node.background then
        self:with_surface(surfaces.background, "background", item, environment.context,
            environment.layout, environment.entry, alpha, function()
                set_color(color(self.styles, item.node.background), alpha)
                love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
            end)
    end
    self:draw_border(item, item.node.border, radius, scale, alpha, surfaces.border, environment)
end

function Renderer:button_background(item, state, scale, alpha, surfaces, environment)
    local style = item.style
    local base = color(self.styles, style.background)
    if not item.enabled then
        base = color(self.styles, style.background_disabled, {base[1], base[2], base[3], base[4] * 0.45})
    elseif state.pressed then
        base = color(self.styles, style.background_pressed, shifted(base, -0.08))
    elseif state.hovered then
        base = color(self.styles, style.background_hovered, shifted(base, 0.07))
    end
    local radius = self:radius(item, scale)
    self:with_surface(surfaces.background, "background", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            set_color(base, alpha)
            love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
        end)

    self:draw_border(item, style.border, radius, scale, alpha, surfaces.border, environment)

    if state.focused then
        local focus = color(self.styles, style.focus or style.foreground)
        local inset = math.max(2, 3 * scale)
        self:with_surface(surfaces.border, "border", item, environment.context,
            environment.layout, environment.entry, alpha, function()
                set_color({focus[1], focus[2], focus[3], 0.7}, alpha)
                love.graphics.setLineWidth(math.max(1, scale))
                love.graphics.rectangle("line", item.rect.x + inset, item.rect.y + inset,
                    item.rect.w - inset * 2, item.rect.h - inset * 2,
                    math.max(0, radius - inset), math.max(0, radius - inset))
            end)
    end
end

function Renderer:text_field(item, state, scale, time, alpha, surfaces, environment)
    local style = item.style
    local base = color(self.styles, style.background)
    if state.focused then base = color(self.styles, style.background_focused, shifted(base, 0.04)) end
    if not item.enabled then base[4] = base[4] * 0.5 end
    local radius = self:radius(item, scale)
    self:with_surface(surfaces.background, "background", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            set_color(base, alpha)
            love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
        end)

    local border_value = state.focused and (style.border_focused or style.caret) or style.border
    self:draw_border(item, border_value, radius, scale, alpha, surfaces.border, environment)

    local padding_x = Layout.resolve_length(style.padding_x or 0, item.rect.w,
        {styles = self.styles, scale = scale}) or 0
    local font = item.font
    local value = item.editor:value()
    local display = value ~= "" and value or tostring(item.node.placeholder or "")
    local clip_x = item.rect.x + padding_x
    local clip_w = math.max(0, item.rect.w - padding_x * 2)
    local caret_offset = font:getWidth(item.editor:prefix(item.editor.cursor))
    local scroll_x = item.editor.scroll_x or 0
    if caret_offset - scroll_x > clip_w then
        scroll_x = caret_offset - clip_w
    elseif caret_offset - scroll_x < 0 then
        scroll_x = caret_offset
    end
    scroll_x = math.max(0, scroll_x)
    item.editor.scroll_x = scroll_x
    local text_x = clip_x - scroll_x
    local text_y = item.rect.y + (item.rect.h - font:getHeight()) / 2
    local previous_x, previous_y, previous_w, previous_h = love.graphics.getScissor()
    local visual_clip = item.visual_rect or item.rect
    love.graphics.setScissor(visual_clip.x, visual_clip.y, visual_clip.w, visual_clip.h)

    self:with_surface(surfaces.content, "content", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            if state.focused and item.editor:has_selection() then
                local first, last = item.editor:selection()
                local selection_x = text_x + font:getWidth(item.editor:prefix(first))
                local selection_w = font:getWidth(item.editor:prefix(last)) - font:getWidth(item.editor:prefix(first))
                set_color(color(self.styles, style.selection), alpha)
                love.graphics.rectangle("fill", selection_x, text_y, selection_w, font:getHeight())
            end

            love.graphics.setFont(font)
            local foreground = value ~= "" and style.foreground or (style.placeholder or style.foreground)
            local text_color = color(self.styles, foreground)
            if value == "" then text_color[4] = text_color[4] * 0.55 end
            if not item.enabled then text_color[4] = text_color[4] * 0.5 end
            set_color(text_color, alpha)
            love.graphics.print(display, math.floor(text_x + 0.5), math.floor(text_y + 0.5))

            if state.focused and not item.editor:has_selection() and (time % 1) < 0.5 then
                local caret_x = text_x + font:getWidth(item.editor:prefix(item.editor.cursor))
                set_color(color(self.styles, style.caret or style.foreground), alpha)
                love.graphics.rectangle("fill", math.floor(caret_x + 0.5), text_y,
                    math.max(1, scale), font:getHeight())
            end
        end)
    if previous_x then
        love.graphics.setScissor(previous_x, previous_y, previous_w, previous_h)
    else
        love.graphics.setScissor()
    end
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
        pressed = context:is_pressed(entry, item.node.id),
        focused = context:is_focused(entry, item.node.id),
    }
    local environment = {context = context, layout = layout, entry = entry}
    if item.kind == "screen" or item.kind == "panel" or item.kind == "row"
        or item.kind == "column" or item.kind == "stack"
    then
        self:container(item, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "button" then
        self:button_background(item, state, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "text_field" then
        self:text_field(item, state, layout.scale, context.time, alpha, surfaces, environment)
    elseif item.kind == "text" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            love.graphics.setFont(item.font)
            set_color(color(self.styles, item.node.color or item.text_style.color), alpha)
            local x = item.rect.x
            if item.node.align == "center" then x = item.rect.x + (item.rect.w - item.font:getWidth(item.text)) / 2
            elseif item.node.align == "right" then x = item.rect.x + item.rect.w - item.font:getWidth(item.text) end
            love.graphics.print(item.text, math.floor(x + 0.5), math.floor(item.rect.y + 0.5))
        end)
    elseif item.kind == "icon" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            local tint = item.node.tint and color(self.styles, item.node.tint) or nil
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
