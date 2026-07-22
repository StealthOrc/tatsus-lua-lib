local utf8 = require("utf8")
local Nodes = require("ui2d.core.nodes")
local LayoutValues = require("ui2d.core.layout_values")
local RenderValues = require("ui2d.core.render_values")
local Transform = require("ui2d.core.transform")

local TextField = {}

local TextEditor = {}
TextEditor.__index = TextEditor

Nodes.register("text_field")

local function characters(value)
    local result = {}
    for _, codepoint in utf8.codes(tostring(value or "")) do
        result[#result + 1] = utf8.char(codepoint)
    end
    return result
end

local function join(chars)
    return table.concat(chars)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function class(character)
    if character == nil or character == "" then
        return "none"
    elseif character:match("%s") then
        return "space"
    elseif character:match("[%w_]") then
        return "word"
    end
    return "separator"
end

function TextEditor.new(options)
    options = options or {}
    local chars = characters(options.value)
    local cursor = clamp(options.cursor or #chars, 0, #chars)
    return setmetatable({
        chars = chars,
        cursor = cursor,
        anchor = cursor,
        max_length = options.max_length,
        filter = options.filter,
    }, TextEditor)
end

function TextEditor:value()
    return join(self.chars)
end

function TextEditor:length()
    return #self.chars
end

function TextEditor:set_value(value, select_all)
    self.chars = characters(value)
    self.cursor = #self.chars
    self.anchor = select_all and 0 or self.cursor
end

function TextEditor:selection()
    return math.min(self.anchor, self.cursor), math.max(self.anchor, self.cursor)
end

function TextEditor:has_selection()
    return self.anchor ~= self.cursor
end

function TextEditor:selected_text()
    local first, last = self:selection()
    return join({unpack(self.chars, first + 1, last)})
end

function TextEditor:select_all()
    self.anchor = 0
    self.cursor = #self.chars
end

function TextEditor:clear_selection()
    self.anchor = self.cursor
end

function TextEditor:replace_selection(value)
    local incoming = characters(value)
    if self.filter then
        local accepted = self.filter(join(incoming), self:value())
        if accepted == false or accepted == nil then
            return false
        end
        if type(accepted) == "string" then
            incoming = characters(accepted)
        end
    end

    local first, last = self:selection()
    local room = self.max_length and math.max(0, self.max_length - (#self.chars - (last - first))) or #incoming
    while #incoming > room do
        table.remove(incoming)
    end

    local next_chars = {}
    for index = 1, first do
        next_chars[#next_chars + 1] = self.chars[index]
    end
    for _, character in ipairs(incoming) do
        next_chars[#next_chars + 1] = character
    end
    for index = last + 1, #self.chars do
        next_chars[#next_chars + 1] = self.chars[index]
    end

    local changed = join(next_chars) ~= self:value()
    self.chars = next_chars
    self.cursor = first + #incoming
    self.anchor = self.cursor
    return changed
end

function TextEditor:insert(value)
    return self:replace_selection(value)
end

function TextEditor:delete_backward(by_word)
    if self:has_selection() then
        return self:replace_selection("")
    end
    if self.cursor == 0 then
        return false
    end
    self.anchor = self.cursor - 1
    if by_word then
        while self.anchor > 0 and class(self.chars[self.anchor + 1]) == "space" do
            self.anchor = self.anchor - 1
        end
        local target_class = class(self.chars[self.anchor + 1])
        while self.anchor > 0 and class(self.chars[self.anchor]) == target_class do
            self.anchor = self.anchor - 1
        end
    end
    return self:replace_selection("")
end

function TextEditor:delete_forward(by_word)
    if self:has_selection() then
        return self:replace_selection("")
    end
    if self.cursor >= #self.chars then
        return false
    end
    self.anchor = self.cursor + 1
    if by_word then
        self.anchor = self.cursor
        while self.anchor < #self.chars and class(self.chars[self.anchor + 1]) == "space" do
            self.anchor = self.anchor + 1
        end
        local target_class = class(self.chars[self.anchor + 1])
        while self.anchor < #self.chars and class(self.chars[self.anchor + 1]) == target_class do
            self.anchor = self.anchor + 1
        end
    end
    return self:replace_selection("")
end

function TextEditor:move_to(position, selecting)
    self.cursor = clamp(position, 0, #self.chars)
    if not selecting then
        self.anchor = self.cursor
    end
end

function TextEditor:move(direction, selecting, by_word)
    local target = self.cursor + direction
    if not selecting and self:has_selection() and not by_word then
        local first, last = self:selection()
        target = direction < 0 and first or last
    elseif by_word then
        if direction < 0 then
            target = self.cursor
            while target > 0 and class(self.chars[target]) == "space" do
                target = target - 1
            end
            local target_class = class(self.chars[target])
            while target > 0 and class(self.chars[target]) == target_class do
                target = target - 1
            end
        else
            target = self.cursor
            while target < #self.chars and class(self.chars[target + 1]) == "space" do
                target = target + 1
            end
            local target_class = class(self.chars[target + 1])
            while target < #self.chars and class(self.chars[target + 1]) == target_class do
                target = target + 1
            end
        end
    end
    self:move_to(target, selecting)
end

function TextEditor:prefix(position)
    return join({unpack(self.chars, 1, clamp(position, 0, #self.chars))})
end

function TextField.new(spec)
    return Nodes.construct("text_field", spec)
end

function TextField.measure(node, available_w, available_h, env)
    assert(type(node.id) == "string" and node.id ~= "", "text_field requires a non-empty id")
    local style = LayoutValues.overlay_style(env.styles:text_field_style(node.style), node)
    local text_style = env.fonts:text_style(node.text_style or style.text)
    local font = env.fonts:get(text_style, env.scale)
    local min_w = LayoutValues.length(style.min_width or 0, available_w, env) or 0
    local min_h = LayoutValues.length(style.min_height or 0, available_h, env) or 0
    local padding_x = LayoutValues.length(style.padding_x or 0, available_w, env) or 0
    local padding_y = LayoutValues.length(style.padding_y or 0, available_h, env) or 0
    return {
        kind = "text_field",
        node = node,
        style = style,
        text_style = text_style,
        font = font,
        editor = env.editor_for(node),
        padding = {
            left = padding_x,
            right = padding_x,
            top = padding_y,
            bottom = padding_y,
        },
        enabled = node.enabled ~= false,
        interactive = true,
        w = math.max(min_w,
            LayoutValues.dimension(node.width, available_w, min_w, env)),
        h = math.max(min_h,
            LayoutValues.dimension(node.height, available_h, min_h, env)),
    }
end

function TextField.editor_for(editors, node, focused)
    local editor = editors[node.id]
    if not editor then
        editor = TextEditor.new {
            value = node.value,
            max_length = node.max_length,
            filter = node.filter,
        }
        editors[node.id] = editor
    else
        editor.max_length = node.max_length
        editor.filter = node.filter
        if node.value ~= nil and not focused and tostring(node.value) ~= editor:value() then
            editor:set_value(node.value)
        end
    end
    return editor
end

function TextField.move_pointer(item, x, y, selecting)
    local padding_x = LayoutValues.length(
        item.style.padding_x or 0, item.rect.w, item.env) or 0
    local transformed_x = Transform.unapply(item.world_transform, x, y)
    local local_x = (transformed_x or x) - item.rect.x - padding_x
        + (item.editor.scroll_x or 0)
    if local_x <= 0 then
        item.editor:move_to(0, selecting)
        return
    end
    local previous = 0
    for position = 1, item.editor:length() do
        local current = item.font:getWidth(item.editor:prefix(position))
        if local_x <= (previous + current) / 2 then
            item.editor:move_to(position - 1, selecting)
            return
        end
        previous = current
    end
    item.editor:move_to(item.editor:length(), selecting)
end

function TextField.keypressed(editor, key, modifiers)
    local shortcut = modifiers.ctrl or modifiers.command
    local result = {handled = true, changed = false}
    if shortcut and key == "a" then
        editor:select_all()
    elseif shortcut and key == "c" then
        if editor:has_selection() then love.system.setClipboardText(editor:selected_text()) end
    elseif shortcut and key == "x" then
        if editor:has_selection() then
            love.system.setClipboardText(editor:selected_text())
            result.changed = editor:replace_selection("")
        end
    elseif shortcut and key == "v" then
        result.changed = editor:insert(love.system.getClipboardText() or "")
    elseif key == "backspace" then
        result.changed = editor:delete_backward(shortcut)
    elseif key == "delete" then
        result.changed = editor:delete_forward(shortcut)
    elseif key == "left" then
        editor:move(-1, modifiers.shift, shortcut)
    elseif key == "right" then
        editor:move(1, modifiers.shift, shortcut)
    elseif key == "home" then
        editor:move_to(0, modifiers.shift)
    elseif key == "end" then
        editor:move_to(editor:length(), modifiers.shift)
    elseif key == "return" or key == "kpenter" then
        result.submit = true
    elseif key == "escape" then
        result.blur = true
    else
        result.handled = false
    end
    return result
end

function TextField.textinput(editor, value)
    return editor:insert(value or "")
end

function TextField.draw(renderer, item, state, scale, time, alpha, surfaces, environment)
    local styles = item.styles or renderer.styles
    local style = item.style
    local base = RenderValues.color(styles, style.background)
    local interaction = {}
    if state.focused then
        interaction = RenderValues.interaction_style(item, "focused")
        base = RenderValues.color(styles, interaction.background or style.background_focused,
            RenderValues.shifted(base, 0.04))
    end
    if state.selected and not state.focused then
        interaction = RenderValues.interaction_style(item, "selected")
        base = RenderValues.color(styles,
            interaction.background or style.background_selected or style.background_focused,
            RenderValues.shifted(base, 0.04))
    end
    if not item.enabled then base[4] = base[4] * 0.5 end

    local radius = renderer:radius(item, scale)
    renderer:with_surface(surfaces.background, "background", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            RenderValues.set_color(base, alpha)
            love.graphics.rectangle("fill",
                item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
        end)

    local border_value = interaction.border or ((state.focused or state.selected)
        and (style.border_selected or style.border_focused or style.caret) or style.border)
    renderer:draw_border(item, border_value,
        radius, scale, alpha, surfaces.border, environment)

    local padding_x = LayoutValues.length(
        style.padding_x or 0, item.rect.w, item.env) or 0
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

    renderer:with_surface(surfaces.content, "content", item, environment.context,
        environment.layout, environment.entry, alpha, function()
            if state.focused and item.editor:has_selection() then
                local first, last = item.editor:selection()
                local selection_x = text_x + font:getWidth(item.editor:prefix(first))
                local selection_w = font:getWidth(item.editor:prefix(last))
                    - font:getWidth(item.editor:prefix(first))
                RenderValues.set_color(RenderValues.color(styles, style.selection), alpha)
                love.graphics.rectangle("fill",
                    selection_x, text_y, selection_w, font:getHeight())
            end

            love.graphics.setFont(font)
            local foreground = value ~= ""
                and style.foreground or (style.placeholder or style.foreground)
            local text_color = RenderValues.color(styles, foreground)
            if value == "" then text_color[4] = text_color[4] * 0.55 end
            if not item.enabled then text_color[4] = text_color[4] * 0.5 end
            RenderValues.set_color(text_color, alpha)
            love.graphics.print(display,
                math.floor(text_x + 0.5), math.floor(text_y + 0.5))

            if state.focused and not item.editor:has_selection() and (time % 1) < 0.5 then
                local caret_x = text_x + font:getWidth(item.editor:prefix(item.editor.cursor))
                RenderValues.set_color(
                    RenderValues.color(styles, style.caret or style.foreground), alpha)
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

function TextField.new_editor(options)
    return TextEditor.new(options)
end

TextField.Editor = TextEditor

return TextField
