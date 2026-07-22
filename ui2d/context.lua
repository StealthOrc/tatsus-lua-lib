local StyleSheet = require("ui2d.style_sheet")
local FontCache = require("ui2d.font_cache")
local TextEditor = require("ui2d.text_editor")
local Svg = require("ui2d.svg")
local Layout = require("ui2d.layout")
local Renderer = require("ui2d.renderer")
local LayerStack = require("ui2d.layer_stack")
local Transform = require("ui2d.transform")
local Motion = require("ui2d.motion")
local Shader = require("ui2d.shader")

local Context = {}
Context.__index = Context

local function point_in_item(item, x, y)
    return item and Transform.contains(item.world_transform, item.rect, x, y)
end

local function same_handle(handle, key, id)
    return handle and handle.key == key and handle.id == id
end

local function action_value(action, source_id, extra, view_key)
    local result
    if type(action) == "string" then
        result = {type = action}
    elseif type(action) == "table" then
        result = StyleSheet.copy(action)
    else
        return nil
    end
    if result.source == nil then result.source = source_id end
    if result.view == nil then result.view = view_key end
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function drag_values(capture, x, y)
    return {
        x = x,
        y = y,
        dx = x - capture.last_x,
        dy = y - capture.last_y,
        total_dx = x - capture.start_x,
        total_dy = y - capture.start_y,
    }
end

function Context.new(config)
    config = config or {}
    local styles = config.styles
    if getmetatable(styles) ~= StyleSheet then styles = StyleSheet.new(styles or {}) end
    local icons = Svg.Cache.new(config.icons)
    local shaders = Shader.Cache.new(config.shaders)
    return setmetatable({
        styles = styles,
        icons = icons,
        shaders = shaders,
        fonts = FontCache.new(styles),
        renderer = Renderer.new(styles, icons, shaders),
        dispatch = config.dispatch,
        layers = LayerStack.new(config.layers),
        motion = Motion.new(),
        editors = {},
        actions = {},
        time = 0,
        pointer_x = 0,
        pointer_y = 0,
    }, Context)
end

function Context:show(view, options)
    local cancelled_pointer_button = self.pointer_capture and 1 or self.cancelled_pointer_button
    self.layers:clear()
    self.motion = Motion.new()
    self.editors = {}
    self.hovered, self.pressed, self.focused = nil, nil, nil
    self.pointer_capture, self.keyboard_pressed = nil, nil
    self.cancelled_pointer_button = cancelled_pointer_button
    options = StyleSheet.copy(options or {})
    if options.layer == nil then options.layer = "base" end
    self:push(view, options)
    return self
end

function Context:push(view, options)
    assert(type(view) == "table" and view.__ui2d_view, "push expects UI.view")
    options = options or {}
    local key = options.key or view.id
    local existing = self.layers:get(key)
    if existing and existing.exiting then
        existing.exiting = false
        existing.view = view
        existing.model = options.model or existing.model
        self.motion:enter_layer(existing)
        return existing.key
    elseif existing then
        existing.view = view
        if options.model ~= nil then existing.model = options.model end
        return existing.key
    end
    local entry = self.layers:push(view, options)
    self.editors[entry.key] = self.editors[entry.key] or {}
    self.motion:add_layer(entry)
    return entry.key
end

function Context:discard(key)
    local entry = self.layers:remove(key)
    if not entry then return false end
    self.editors[key] = nil
    self.motion:remove_layer(key)
    if self.hovered and self.hovered.key == key then self.hovered = nil end
    if self.pressed and self.pressed.key == key then self.pressed = nil end
    if self.focused and self.focused.key == key then self.focused = nil end
    if self.pointer_capture and self.pointer_capture.key == key then
        self.pointer_capture = nil
        self.cancelled_pointer_button = 1
    end
    if self.keyboard_pressed and self.keyboard_pressed.key == key then self.keyboard_pressed = nil end
    self:update_hover()
    return true
end

function Context:remove(key)
    local entry = self.layers:get(key)
    if not entry then return false end
    if entry.exiting then return true end
    if entry.transition and self.motion:exit_layer(entry) then
        entry.exiting = true
        if self.pointer_capture and self.pointer_capture.key == key then
            self.pointer_capture = nil
            self.cancelled_pointer_button = 1
        end
        if self.keyboard_pressed and self.keyboard_pressed.key == key then self.keyboard_pressed = nil end
        return true
    end
    return self:discard(key)
end

function Context:pop()
    local entry = self.layers.entries[#self.layers.entries]
    return entry and self:remove(entry.key) or false
end

function Context:model_value(entry)
    return type(entry.model) == "function" and entry.model() or entry.model
end

function Context:editor_for(entry, node)
    local editors = self.editors[entry.key]
    local editor = editors[node.id]
    if not editor then
        editor = TextEditor.new {value = node.value, max_length = node.max_length, filter = node.filter}
        editors[node.id] = editor
    else
        editor.max_length = node.max_length
        editor.filter = node.filter
        if node.value ~= nil and not same_handle(self.focused, entry.key, node.id)
            and tostring(node.value) ~= editor:value()
        then
            editor:set_value(node.value)
        end
    end
    return editor
end

function Context:rebuild()
    local width, height = love.graphics.getDimensions()
    for _, entry in ipairs(self.layers.entries) do
        local root = entry.view.build(self:model_value(entry) or {})
        entry.layout = Layout.build(root, width, height, {
            styles = self.styles,
            fonts = self.fonts,
            icons = self.icons,
            editor_for = function(node) return self:editor_for(entry, node) end,
        })
        self.motion:reconcile(entry, entry.layout, self)
        self.motion:apply(entry)
    end
    if self.focused then
        local entry = self.layers:get(self.focused.key)
        if not entry or not entry.layout.by_id[self.focused.id] then self.focused = nil end
    end
    self:update_hover()
end

function Context:queue(action, source_id, extra, view_key)
    local value = action_value(action, source_id, extra, view_key)
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
    self.motion:update(dt or 0)
    for _, entry in ipairs(self.layers.entries) do self.motion:apply(entry) end
    local exited = {}
    for _, entry in ipairs(self.layers.entries) do
        if entry.exiting and self.motion:layer_exited(entry) then exited[#exited + 1] = entry.key end
    end
    for _, key in ipairs(exited) do self:discard(key) end
    self:update_hover()
end

function Context:draw()
    if #self.layers.entries > 0 and not self.layers.entries[1].layout then self:rebuild() end
    for _, entry in ipairs(self.layers.entries) do
        self.renderer:draw(entry.layout, self, entry)
    end
end

function Context:route_at(x, y)
    for index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[index]
        local layout = entry.layout
        if layout then
            for region_index = #layout.hit_regions, 1, -1 do
                local region = layout.hit_regions[region_index]
                if point_in_item(region.item, x, y) then
                    return {
                        entry = entry,
                        item = region.interactive and region.item or nil,
                        blocker = region.blocks and region.item or nil,
                        consumed = true,
                    }
                end
            end
            if entry.pointer ~= "pass" or layout.modal then
                return {entry = entry, consumed = true}
            end
        end
    end
    return {consumed = false}
end

function Context:item_at(x, y)
    return self:route_at(x, y).item
end

function Context:update_hover()
    local route = self:route_at(self.pointer_x, self.pointer_y)
    local item = route.item
    local next_hovered = item and item.enabled and {key = route.entry.key, id = item.node.id} or nil
    local unchanged = (self.hovered == nil and next_hovered == nil)
        or (self.hovered and next_hovered
            and self.hovered.key == next_hovered.key and self.hovered.id == next_hovered.id)
    if unchanged then return end

    local previous = self.hovered
    self.hovered = next_hovered
    if previous then
        local entry = self.layers:get(previous.key)
        local previous_item = entry and entry.layout and entry.layout.by_id[previous.id]
        if previous_item then
            self:queue(previous_item.node.hover_leave, previous.id, nil, previous.key)
        end
    end
    if next_hovered then
        self:queue(item.node.hover_enter, item.node.id, nil, route.entry.key)
    end
end

function Context:is_hovered(entry, id)
    return same_handle(self.hovered, entry.key, id)
end

function Context:is_pressed(entry, id)
    return same_handle(self.pressed, entry.key, id)
end

function Context:is_focused(entry, id)
    return same_handle(self.focused, entry.key, id)
end

function Context:cursor_from_x(item, x)
    local style = item.style
    local padding_x = Layout.resolve_length(style.padding_x or 0, item.rect.w, {
        styles = self.styles,
        scale = item.layout_scale,
    }) or 0
    local transformed_x = Transform.unapply(item.world_transform, x, self.pointer_y)
    local local_x = (transformed_x or x) - item.rect.x - padding_x + (item.editor.scroll_x or 0)
    if local_x <= 0 then return 0 end
    local previous = 0
    for position = 1, item.editor:length() do
        local current = item.font:getWidth(item.editor:prefix(position))
        if local_x <= (previous + current) / 2 then return position - 1 end
        previous = current
    end
    return item.editor:length()
end

function Context:emit_editor_change(entry, item)
    self:queue(item.node.changed or item.node.change_action, item.node.id,
        {value = item.editor:value()}, entry.key)
end

function Context:modifiers()
    return {
        ctrl = love.keyboard.isDown("lctrl", "rctrl"),
        command = love.keyboard.isDown("lgui", "rgui"),
        shift = love.keyboard.isDown("lshift", "rshift"),
        alt = love.keyboard.isDown("lalt", "ralt"),
    }
end

function Context:keyboard_owner()
    for index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[index]
        if entry.keyboard ~= "pass" then return entry end
    end
    return nil
end

function Context:focus_adjacent(direction)
    local entry = self:keyboard_owner()
    local layout = entry and entry.layout
    if not layout or #layout.interactive == 0 then return false end
    local current = 0
    for index, item in ipairs(layout.interactive) do
        if same_handle(self.focused, entry.key, item.node.id) then current = index break end
    end
    for step = 1, #layout.interactive do
        local index = ((current - 1 + direction * step) % #layout.interactive) + 1
        local item = layout.interactive[index]
        if item.enabled then
            self.focused = {key = entry.key, id = item.node.id}
            return true
        end
    end
    return false
end

function Context:field_keypressed(entry, item, key)
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
        self:queue(item.node.submit, item.node.id, {value = editor:value()}, entry.key)
    elseif key == "escape" then
        self.focused = nil
    else
        return false
    end
    if changed then self:emit_editor_change(entry, item) end
    return true
end

function Context:event(name, ...)
    if #self.layers.entries > 0 and not self.layers.entries[1].layout then self:rebuild() end
    local args = {...}
    if name == "resize" then
        self:rebuild()
        return #self.layers.entries > 0
    elseif name == "focus" and args[1] == false then
        self.pressed, self.pointer_capture, self.keyboard_pressed = nil, nil, nil
        self.cancelled_pointer_button = nil
        return false
    elseif name == "mousemoved" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        local capture = self.pointer_capture
        if capture then
            local entry = self.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            if item and capture.draggable then
                local values = drag_values(capture, self.pointer_x, self.pointer_y)
                self:queue(item.node.dragged, item.node.id, values, entry.key)
            end
            capture.last_x, capture.last_y = self.pointer_x, self.pointer_y
        end
        if capture and capture.kind == "text_field" then
            local entry = self.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            if item then item.editor:move_to(self:cursor_from_x(item, self.pointer_x), true) end
        end
        self:update_hover()
        return self.pointer_capture ~= nil or self:route_at(self.pointer_x, self.pointer_y).consumed
    elseif name == "mousepressed" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        if self.cancelled_pointer_button == args[3] then self.cancelled_pointer_button = nil end
        local route = self:route_at(self.pointer_x, self.pointer_y)
        local item = route.item
        if args[3] == 1 and item and item.enabled then
            local handle = {key = route.entry.key, id = item.node.id}
            self.focused, self.pressed = handle, {key = handle.key, id = handle.id}
            self.pointer_capture = {
                key = handle.key,
                id = handle.id,
                kind = item.kind,
                start_x = self.pointer_x,
                start_y = self.pointer_y,
                last_x = self.pointer_x,
                last_y = self.pointer_y,
                draggable = item.node.drag_started ~= nil or item.node.dragged ~= nil
                    or item.node.drag_ended ~= nil,
            }
            if item.kind == "text_field" then
                item.editor:move_to(self:cursor_from_x(item, self.pointer_x), false)
            end
            self:queue(item.node.drag_started, item.node.id, {
                x = self.pointer_x,
                y = self.pointer_y,
                dx = 0,
                dy = 0,
                total_dx = 0,
                total_dy = 0,
            }, route.entry.key)
            if item.kind == "button" then
                self:queue(item.node.action, item.node.id, nil, route.entry.key)
            end
            self:update_hover()
            return true
        end
        self.focused = nil
        return route.consumed
    elseif name == "wheelmoved" then
        return self:route_at(self.pointer_x, self.pointer_y).consumed
    elseif name == "mousereleased" then
        self.pointer_x, self.pointer_y = args[1], args[2]
        if self.cancelled_pointer_button == args[3] then
            self.cancelled_pointer_button = nil
            self.pressed = nil
            self:update_hover()
            return true
        end
        local capture = self.pointer_capture
        if args[3] == 1 and capture then
            local entry = self.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            local values = drag_values(capture, self.pointer_x, self.pointer_y)
            if item and capture.draggable then
                self:queue(item.node.drag_ended, item.node.id, values, entry.key)
            end
            self.pressed, self.pointer_capture = nil, nil
            self:update_hover()
            return true
        end
        return self:route_at(self.pointer_x, self.pointer_y).consumed
    elseif name == "keypressed" then
        local key = args[1]
        if key == "tab" then return self:focus_adjacent(self:modifiers().shift and -1 or 1) end
        local owner = self:keyboard_owner()
        local entry = self.focused and self.layers:get(self.focused.key)
        local item = entry and owner == entry and entry.layout.by_id[self.focused.id]
        if item and item.enabled then
            if item.kind == "text_field" then return self:field_keypressed(entry, item, key) end
            if item.kind == "button" and (key == "space" or key == "return" or key == "kpenter") then
                self.pressed = {key = entry.key, id = item.node.id}
                self.keyboard_pressed = {key = entry.key, id = item.node.id}
                self:queue(item.node.action, item.node.id, nil, entry.key)
                return true
            end
        end
        return owner ~= nil
    elseif name == "keyreleased" then
        local key = args[1]
        if self.keyboard_pressed and (key == "space" or key == "return" or key == "kpenter") then
            self.keyboard_pressed, self.pressed = nil, nil
            return true
        end
        return self:keyboard_owner() ~= nil
    elseif name == "textinput" then
        local owner = self:keyboard_owner()
        local entry = self.focused and self.layers:get(self.focused.key)
        local item = entry and owner == entry and entry.layout.by_id[self.focused.id]
        if item and item.kind == "text_field" and item.enabled then
            if item.editor:insert(args[1] or "") then self:emit_editor_change(entry, item) end
            return true
        end
        return owner ~= nil
    end
    return false
end

function Context:rect(id, view_key)
    if view_key then
        local entry = self.layers:get(view_key)
        local item = entry and entry.layout and entry.layout.by_id[id]
        return item and StyleSheet.copy(item.visual_rect or item.rect) or nil
    end
    for index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[index]
        local item = entry.layout and entry.layout.by_id[id]
        if item then return StyleSheet.copy(item.visual_rect or item.rect) end
    end
    return nil
end

return Context
