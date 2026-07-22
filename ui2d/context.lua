local StyleSheet = require("ui2d.style_sheet")
local FontCache = require("ui2d.font_cache")
local TextEditor = require("ui2d.text_editor")
local Svg = require("ui2d.svg")
local Layout = require("ui2d.layout")
local Renderer = require("ui2d.renderer")

local Context = {}
Context.__index = Context

local function point_in(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function action_value(action, source_id, extra)
    local result
    if type(action) == "string" then
        result = {type = action}
    elseif type(action) == "table" then
        result = StyleSheet.copy(action)
    else
        return nil
    end
    if result.source == nil then result.source = source_id end
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

function Context.new(config)
    config = config or {}
    local styles = config.styles
    if getmetatable(styles) ~= StyleSheet then styles = StyleSheet.new(styles or {}) end
    local icons = Svg.Cache.new(config.icons)
    local self = setmetatable({
        styles = styles,
        icons = icons,
        fonts = FontCache.new(styles),
        renderer = Renderer.new(styles, icons),
        dispatch = config.dispatch,
        editors = {},
        actions = {},
        time = 0,
        pointer_x = 0,
        pointer_y = 0,
    }, Context)
    return self
end

function Context:show(view, options)
    assert(type(view) == "table" and view.__ui2d_view, "show expects UI.view")
    options = options or {}
    self.view = view
    self.model = options.model or {}
    self.layout = nil
    self.hovered_id = nil
    self.pressed_id = nil
    self.focused_id = nil
    self.pointer_capture = nil
    return self
end

function Context:model_value()
    return type(self.model) == "function" and self.model() or self.model
end

function Context:editor_for(node)
    local editor = self.editors[node.id]
    if not editor then
        editor = TextEditor.new {
            value = node.value,
            max_length = node.max_length,
            filter = node.filter,
        }
        self.editors[node.id] = editor
    else
        editor.max_length = node.max_length
        editor.filter = node.filter
        if node.value ~= nil and self.focused_id ~= node.id and tostring(node.value) ~= editor:value() then
            editor:set_value(node.value)
        end
    end
    return editor
end

function Context:rebuild()
    if not self.view then return end
    local root = self.view.build(self:model_value() or {})
    local width, height = love.graphics.getDimensions()
    self.layout = Layout.build(root, width, height, {
        styles = self.styles,
        fonts = self.fonts,
        icons = self.icons,
        editor_for = function(node) return self:editor_for(node) end,
    })
    if self.focused_id and not self.layout.by_id[self.focused_id] then self.focused_id = nil end
    self:update_hover()
end

function Context:queue(action, source_id, extra)
    local value = action_value(action, source_id, extra)
    if value then self.actions[#self.actions + 1] = value end
end

function Context:take_actions()
    local actions = self.actions
    self.actions = {}
    return actions
end

function Context:update(dt)
    self.time = self.time + (dt or 0)
    if self.dispatch then
        for _, action in ipairs(self:take_actions()) do self.dispatch(action) end
    end
    self:rebuild()
end

function Context:draw()
    if not self.layout then self:rebuild() end
    self.renderer:draw(self.layout, self)
end

function Context:item_at(x, y)
    if not self.layout then return nil end
    for index = #self.layout.interactive, 1, -1 do
        local item = self.layout.interactive[index]
        if point_in(item.rect, x, y) then return item end
    end
    return nil
end

function Context:update_hover()
    local item = self:item_at(self.pointer_x, self.pointer_y)
    self.hovered_id = item and item.enabled and item.node.id or nil
end

function Context:cursor_from_x(item, x)
    local style = item.style
    local padding_x = Layout.resolve_length(style.padding_x or 0, item.rect.w, {
        styles = self.styles,
        scale = self.layout.scale,
    }) or 0
    local local_x = x - item.rect.x - padding_x + (item.editor.scroll_x or 0)
    if local_x <= 0 then return 0 end
    local previous = 0
    for position = 1, item.editor:length() do
        local current = item.font:getWidth(item.editor:prefix(position))
        if local_x <= (previous + current) / 2 then return position - 1 end
        previous = current
    end
    return item.editor:length()
end

function Context:emit_editor_change(item)
    self:queue(item.node.changed or item.node.change_action, item.node.id, {value = item.editor:value()})
end

function Context:modifiers()
    return {
        ctrl = love.keyboard.isDown("lctrl", "rctrl"),
        command = love.keyboard.isDown("lgui", "rgui"),
        shift = love.keyboard.isDown("lshift", "rshift"),
        alt = love.keyboard.isDown("lalt", "ralt"),
    }
end

function Context:focus_adjacent(direction)
    if not self.layout or #self.layout.interactive == 0 then return false end
    local current = 0
    for index, item in ipairs(self.layout.interactive) do
        if item.node.id == self.focused_id then current = index break end
    end
    for step = 1, #self.layout.interactive do
        local index = ((current - 1 + direction * step) % #self.layout.interactive) + 1
        local item = self.layout.interactive[index]
        if item.enabled then
            self.focused_id = item.node.id
            return true
        end
    end
    return false
end

function Context:field_keypressed(item, key)
    local editor = item.editor
    local modifiers = self:modifiers()
    local shortcut = modifiers.ctrl or modifiers.command
    local changed = false
    if shortcut and key == "a" then
        editor:select_all()
    elseif shortcut and key == "c" then
        if editor:has_selection() then love.system.setClipboardText(editor:selected_text()) end
    elseif shortcut and key == "x" then
        if editor:has_selection() then
            love.system.setClipboardText(editor:selected_text())
            changed = editor:replace_selection("")
        end
    elseif shortcut and key == "v" then
        changed = editor:insert(love.system.getClipboardText() or "")
    elseif key == "backspace" then
        changed = editor:delete_backward(shortcut)
    elseif key == "delete" then
        changed = editor:delete_forward(shortcut)
    elseif key == "left" then
        editor:move(-1, modifiers.shift, shortcut)
    elseif key == "right" then
        editor:move(1, modifiers.shift, shortcut)
    elseif key == "home" then
        editor:move_to(0, modifiers.shift)
    elseif key == "end" then
        editor:move_to(editor:length(), modifiers.shift)
    elseif key == "return" or key == "kpenter" then
        self:queue(item.node.submit, item.node.id, {value = editor:value()})
    elseif key == "escape" then
        self.focused_id = nil
    else
        return false
    end
    if changed then self:emit_editor_change(item) end
    return true
end

function Context:event(name, ...)
    if not self.layout and self.view then self:rebuild() end
    local args = {...}
    if name == "resize" then
        self:rebuild()
        return self.layout and self.layout.modal or false
    elseif name == "focus" and args[1] == false then
        self.pressed_id, self.pointer_capture, self.keyboard_pressed_id = nil, nil, nil
        return false
    elseif name == "mousemoved" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        if self.pointer_capture and self.pointer_capture.kind == "text_field" then
            local item = self.layout.by_id[self.pointer_capture.id]
            if item then item.editor:move_to(self:cursor_from_x(item, self.pointer_x), true) end
        end
        self:update_hover()
        return self.pointer_capture ~= nil or self.hovered_id ~= nil or (self.layout and self.layout.modal)
    elseif name == "mousepressed" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        local button = args[3]
        local item = button == 1 and self:item_at(self.pointer_x, self.pointer_y) or nil
        if item and item.enabled then
            self.focused_id = item.node.id
            self.pressed_id = item.node.id
            self.pointer_capture = {id = item.node.id, kind = item.kind}
            if item.kind == "text_field" then
                local cursor = self:cursor_from_x(item, self.pointer_x)
                item.editor:move_to(cursor, false)
            end
            self:update_hover()
            return true
        end
        self.focused_id = nil
        return self.layout and self.layout.modal or false
    elseif name == "mousereleased" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        local button = args[3]
        local capture = self.pointer_capture
        if button == 1 and capture then
            local item = self.layout.by_id[capture.id]
            if item and item.kind == "button" and item.enabled and point_in(item.rect, self.pointer_x, self.pointer_y) then
                self:queue(item.node.action, item.node.id)
            end
            self.pressed_id, self.pointer_capture = nil, nil
            self:update_hover()
            return true
        end
        return self.layout and self.layout.modal or false
    elseif name == "keypressed" then
        local key = args[1]
        if key == "tab" then return self:focus_adjacent(self:modifiers().shift and -1 or 1) end
        local item = self.focused_id and self.layout and self.layout.by_id[self.focused_id]
        if item and item.enabled then
            if item.kind == "text_field" then return self:field_keypressed(item, key) end
            if item.kind == "button" and (key == "space" or key == "return" or key == "kpenter") then
                self.pressed_id = item.node.id
                self.keyboard_pressed_id = item.node.id
                return true
            end
        end
        return self.layout and self.layout.modal or false
    elseif name == "keyreleased" then
        local key = args[1]
        if self.keyboard_pressed_id and (key == "space" or key == "return" or key == "kpenter") then
            local item = self.layout and self.layout.by_id[self.keyboard_pressed_id]
            if item and item.enabled and item.node.id == self.focused_id then self:queue(item.node.action, item.node.id) end
            self.keyboard_pressed_id, self.pressed_id = nil, nil
            return true
        end
        return self.layout and self.layout.modal or false
    elseif name == "textinput" then
        local item = self.focused_id and self.layout and self.layout.by_id[self.focused_id]
        if item and item.kind == "text_field" and item.enabled then
            if item.editor:insert(args[1] or "") then self:emit_editor_change(item) end
            return true
        end
        return self.layout and self.layout.modal or false
    end
    return self.layout and self.layout.modal or false
end

function Context:rect(id)
    local item = self.layout and self.layout.by_id[id]
    return item and StyleSheet.copy(item.rect) or nil
end

return Context
