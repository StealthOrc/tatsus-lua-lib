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

function Renderer.new(styles, icons)
    return setmetatable({styles = styles, icons = icons}, Renderer)
end

function Renderer:button_background(item, state, scale)
    local style = item.style
    local base = color(self.styles, style.background)
    if not item.enabled then
        base = color(self.styles, style.background_disabled, {base[1], base[2], base[3], base[4] * 0.45})
    elseif state.pressed then
        base = color(self.styles, style.background_pressed, shifted(base, -0.08))
    elseif state.hovered then
        base = color(self.styles, style.background_hovered, shifted(base, 0.07))
    end
    local radius = Layout.resolve_length(style.radius or 0, math.min(item.rect.w, item.rect.h), {
        styles = self.styles,
        scale = scale,
    }) or 0
    set_color(base)
    love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)

    local border = self.styles:color(style.border)
    if border then
        local border_width = Layout.resolve_length(style.border_width or 1, item.rect.w, {
            styles = self.styles,
            scale = scale,
        }) or 1
        love.graphics.setLineWidth(math.max(1, border_width))
        set_color(color(self.styles, border))
        love.graphics.rectangle("line", item.rect.x + border_width / 2, item.rect.y + border_width / 2,
            item.rect.w - border_width, item.rect.h - border_width, radius, radius)
    end

    if state.focused then
        local focus = color(self.styles, style.focus or style.foreground)
        local inset = math.max(2, 3 * scale)
        set_color({focus[1], focus[2], focus[3], 0.7})
        love.graphics.setLineWidth(math.max(1, scale))
        love.graphics.rectangle("line", item.rect.x + inset, item.rect.y + inset,
            item.rect.w - inset * 2, item.rect.h - inset * 2,
            math.max(0, radius - inset), math.max(0, radius - inset))
    end
end

function Renderer:text_field(item, state, scale, time)
    local style = item.style
    local base = color(self.styles, style.background)
    if state.focused then base = color(self.styles, style.background_focused, shifted(base, 0.04)) end
    if not item.enabled then base[4] = base[4] * 0.5 end
    local radius = Layout.resolve_length(style.radius or 0, math.min(item.rect.w, item.rect.h), {
        styles = self.styles,
        scale = scale,
    }) or 0
    set_color(base)
    love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)

    local border_value = state.focused and (style.border_focused or style.caret) or style.border
    if border_value then
        set_color(color(self.styles, border_value))
        love.graphics.setLineWidth(math.max(1, scale))
        love.graphics.rectangle("line", item.rect.x + scale / 2, item.rect.y + scale / 2,
            item.rect.w - scale, item.rect.h - scale, radius, radius)
    end

    local padding_x = Layout.resolve_length(style.padding_x or 0, item.rect.w, {styles = self.styles, scale = scale}) or 0
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
    love.graphics.setScissor(clip_x, item.rect.y, clip_w, item.rect.h)

    if state.focused and item.editor:has_selection() then
        local first, last = item.editor:selection()
        local selection_x = text_x + font:getWidth(item.editor:prefix(first))
        local selection_w = font:getWidth(item.editor:prefix(last)) - font:getWidth(item.editor:prefix(first))
        set_color(color(self.styles, style.selection))
        love.graphics.rectangle("fill", selection_x, text_y, selection_w, font:getHeight())
    end

    love.graphics.setFont(font)
    local foreground = value ~= "" and style.foreground or (style.placeholder or style.foreground)
    local text_color = color(self.styles, foreground)
    if value == "" then text_color[4] = text_color[4] * 0.55 end
    if not item.enabled then text_color[4] = text_color[4] * 0.5 end
    set_color(text_color)
    love.graphics.print(display, math.floor(text_x + 0.5), math.floor(text_y + 0.5))

    if state.focused and not item.editor:has_selection() and (time % 1) < 0.5 then
        local caret_x = text_x + font:getWidth(item.editor:prefix(item.editor.cursor))
        set_color(color(self.styles, style.caret or style.foreground))
        love.graphics.rectangle("fill", math.floor(caret_x + 0.5), text_y, math.max(1, scale), font:getHeight())
    end
    if previous_x then
        love.graphics.setScissor(previous_x, previous_y, previous_w, previous_h)
    else
        love.graphics.setScissor()
    end
end

local function draw_item(self, item, context, layout)
    local state = {
        hovered = context.hovered_id == item.node.id,
        pressed = context.pressed_id == item.node.id,
        focused = context.focused_id == item.node.id,
    }
    if item.kind == "screen" and item.node.background then
        set_color(color(self.styles, item.node.background))
        love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h)
    elseif item.kind == "button" then
        self:button_background(item, state, layout.scale)
    elseif item.kind == "text_field" then
        self:text_field(item, state, layout.scale, context.time)
    elseif item.kind == "text" then
        love.graphics.setFont(item.font)
        set_color(color(self.styles, item.node.color or item.text_style.color))
        local x = item.rect.x
        if item.node.align == "center" then x = item.rect.x + (item.rect.w - item.font:getWidth(item.text)) / 2
        elseif item.node.align == "right" then x = item.rect.x + item.rect.w - item.font:getWidth(item.text) end
        love.graphics.print(item.text, math.floor(x + 0.5), math.floor(item.rect.y + 0.5))
    elseif item.kind == "icon" then
        local tint = item.node.tint and color(self.styles, item.node.tint) or nil
        self.icons:draw(item.node.name, item.rect.x, item.rect.y, item.rect.w, item.rect.h,
            tint, item.node.alpha or 1)
    end
    for _, child in ipairs(item.children or {}) do
        draw_item(self, child, context, layout)
    end
end

function Renderer:draw(layout, context)
    if not layout then return end
    love.graphics.push("all")
    love.graphics.origin()
    draw_item(self, layout.root, context, layout)
    love.graphics.pop()
end

return Renderer
