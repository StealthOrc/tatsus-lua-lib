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
local Navigation = require("ui2d.navigation")

local Context = {}
Context.__index = Context

local function point_in_item(item, x, y)
    return item and Transform.contains(item.world_transform, item.rect, x, y)
end

local function same_handle(handle, key, id)
    return handle and handle.key == key and handle.id == id
end

local function input_source_kind(source)
    if type(source) == "table" then return source.kind or "navigation" end
    return source or "navigation"
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
        navigation_options = type(config.navigation) == "table" and config.navigation or {},
        navigation_enabled = config.navigation ~= false,
        layers = LayerStack.new(config.layers),
        motion = Motion.new(),
        editors = {},
        actions = {},
        time = 0,
        pointer_x = 0,
        pointer_y = 0,
        selections = {},
        selection_mode = "navigation",
        navigation_input = {x = 0, y = 0},
    }, Context)
end

function Context:show(view, options)
    local cancelled_pointer_button = self.pointer_capture and 1 or self.cancelled_pointer_button
    self.layers:clear()
    self.motion = Motion.new()
    self.editors = {}
    self.hovered, self.pressed, self.focused = nil, nil, nil
    self.selections = {}
    self.selection_mode = "navigation"
    self.navigation_input = {x = 0, y = 0}
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
    self.selections[key] = nil
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
    end
    if self.focused then
        local entry = self.layers:get(self.focused.key)
        if not entry or not entry.layout.by_id[self.focused.id] then self.focused = nil end
    end
    for key, selection in pairs(self.selections) do
        local entry = self.layers:get(key)
        local item = entry and entry.layout and entry.layout.by_id[selection.id]
        if not item or not item.enabled or not item.navigation_enabled then
            local first = entry and entry.layout and Navigation.first(entry.layout,
                entry.navigation_options and entry.navigation_options.initial)
            self.selections[key] = first and {key = key, id = first.node.id} or nil
        end
    end
    for _, entry in ipairs(self.layers.entries) do
        if entry.navigation ~= "pass" and not self.selections[entry.key] and entry.layout then
            local first = Navigation.first(entry.layout, entry.navigation_options.initial)
            if first then self.selections[entry.key] = {key = entry.key, id = first.node.id} end
        end
    end
    self:update_hover()
    for _, entry in ipairs(self.layers.entries) do
        self.motion:reconcile(entry, entry.layout, self)
        self.motion:apply(entry)
    end
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
    local navigation_input = self.navigation_input
    if navigation_input.direction and navigation_input.repeat_at
        and self.time >= navigation_input.repeat_at
    then
        self:navigate(navigation_input.direction, navigation_input.source)
        local repeat_options = self:navigation_options_for(self:navigation_owner())
        navigation_input.repeat_at = self.time
            + (repeat_options.repeat_interval or 0.10)
    end
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

function Context:is_selected(entry, id)
    if self.selection_mode == "pointer" then
        return same_handle(self.hovered, entry.key, id)
    end
    local owner = self:navigation_owner()
    return owner == entry and same_handle(self:navigation_selection(entry), entry.key, id)
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

function Context:navigation_owner()
    if not self.navigation_enabled then return nil end
    for index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[index]
        if entry.navigation ~= "pass" then return entry end
    end
    return nil
end

function Context:navigation_options_for(entry)
    local result = StyleSheet.copy(self.navigation_options)
    StyleSheet.merge(result, entry and entry.navigation_options or {})
    local root = entry and entry.layout and entry.layout.root.node.navigation
    if type(root) == "table" then StyleSheet.merge(result, root) end
    return result
end

function Context:navigation_selection(entry)
    return entry and self.selections[entry.key] or nil
end

function Context:set_navigation_selection(entry, item, source)
    if not entry then return false end
    local previous = self.selections[entry.key]
    local was_active = self.selection_mode ~= "pointer"
    if previous and item and previous.id == item.node.id then
        previous.source = source or previous.source
        self.selection_mode = input_source_kind(source or self.selection_mode)
        if not was_active then
            self:queue(item.node.select_enter, item.node.id,
                {selection_source = source}, entry.key)
        end
        return true
    end
    if previous and was_active then
        local previous_item = entry.layout and entry.layout.by_id[previous.id]
        if previous_item then
            self:queue(previous_item.node.select_leave, previous.id,
                {selection_source = source}, entry.key)
        end
    end
    self.selections[entry.key] = item and {key = entry.key, id = item.node.id, source = source} or nil
    if self.focused and (not item or not same_handle(self.focused, entry.key, item.node.id)) then
        self.focused = nil
    end
    self.selection_mode = input_source_kind(source)
    if item then
        self:queue(item.node.select_enter, item.node.id,
            {selection_source = source}, entry.key)
    end
    return item ~= nil
end

function Context:use_pointer_selection()
    if self.selection_mode == "pointer" then return end
    local entry = self:navigation_owner()
    local selection = self:navigation_selection(entry)
    local item = selection and entry and entry.layout and entry.layout.by_id[selection.id]
    if item then
        self:queue(item.node.select_leave, item.node.id,
            {selection_source = "pointer"}, entry.key)
    end
    self.selection_mode = "pointer"
end

function Context:select(id, view_key, source)
    local entry = view_key and self.layers:get(view_key) or self:navigation_owner()
    local item = entry and entry.layout and entry.layout.by_id[id]
    if not item or not item.navigation_enabled or not item.enabled then return false end
    return self:set_navigation_selection(entry, item, source or "programmatic")
end

function Context:selected()
    local handle
    if self.selection_mode == "pointer" then
        handle = self.hovered
    else
        local entry = self:navigation_owner()
        handle = self:navigation_selection(entry)
    end
    if not handle then return nil end
    return {id = handle.id, view = handle.key,
        source = self.selection_mode == "pointer" and "pointer" or handle.source or self.selection_mode}
end

function Context:navigate(direction, source)
    local entry = self:navigation_owner()
    local layout = entry and entry.layout
    if not layout or #(layout.navigable or {}) == 0 then return false end
    local selection = self:navigation_selection(entry)
    local options = self:navigation_options_for(entry)
    local request = {
        context = self,
        view = entry.key,
        source = source,
        selected = selection and selection.id or nil,
    }
    local target = Navigation.move(layout, selection and selection.id, direction, options, request)
    if target then return self:set_navigation_selection(entry, target, source or "navigation") end
    local current = selection and layout.by_id[selection.id]
    return current and self:set_navigation_selection(entry, current, source or "navigation") or false
end

function Context:focus_adjacent(direction)
    local entry = self:navigation_owner()
    local layout = entry and entry.layout
    if not layout or #layout.interactive == 0 then return false end
    local current = 0
    for index, item in ipairs(layout.interactive) do
        if same_handle(self:navigation_selection(entry), entry.key, item.node.id) then current = index break end
    end
    for step = 1, #layout.interactive do
        local index = ((current - 1 + direction * step) % #layout.interactive) + 1
        local item = layout.interactive[index]
        if item.enabled and item.navigation_enabled then
            return self:set_navigation_selection(entry, item, "keyboard")
        end
    end
    return false
end

function Context:activate_selection(source)
    local entry = self:navigation_owner()
    local selection = self:navigation_selection(entry)
    local item = selection and entry and entry.layout and entry.layout.by_id[selection.id]
    if not item or not item.enabled then return false end
    self:set_navigation_selection(entry, item, source)
    if item.kind == "text_field" then
        self.focused = {key = entry.key, id = item.node.id}
        return true
    end
    if item.kind ~= "button" then return false end
    self.pressed = {key = entry.key, id = item.node.id}
    self.keyboard_pressed = {key = entry.key, id = item.node.id, semantic = true}
    self:queue(item.node.press_started, item.node.id, {input_source = source}, entry.key)
    self:queue(item.node.action, item.node.id, {input_source = source}, entry.key)
    return true
end

function Context:release_selection(source)
    local pressed = self.keyboard_pressed
    if not pressed or not pressed.semantic then return false end
    local entry = self.layers:get(pressed.key)
    local item = entry and entry.layout and entry.layout.by_id[pressed.id]
    if item then self:queue(item.node.press_ended, item.node.id, {input_source = source}, entry.key) end
    self.keyboard_pressed, self.pressed = nil, nil
    return true
end

function Context:input(event)
    assert(type(event) == "table", "ui2d input expects an event table")
    local action = event.action or event.name or event.type
    local source = event.source or "navigation"
    if action == "accept" then
        if event.phase == "released" then return self:release_selection(source) end
        if event.phase == nil or event.phase == "pressed" then return self:activate_selection(source) end
        return false
    elseif action ~= "navigate" then
        return false
    end

    local value = event.value or event
    local x, y = value.x or 0, value.y or 0
    local options = self:navigation_options_for(self:navigation_owner())
    local direction = event.direction or Navigation.direction(x, y,
        event.threshold or options.threshold or 0.5)
    if event.phase == "pressed" and event.direction then
        return self:navigate(event.direction, source)
    end
    if event.phase == "released" or not direction then
        self.navigation_input = {x = x, y = y}
        return false
    end
    local held = self.navigation_input
    local changed = held.direction ~= direction
    self.navigation_input = {
        x = x,
        y = y,
        direction = direction,
        source = source,
        repeat_at = changed and (self.time + (options.repeat_delay or 0.35))
            or held.repeat_at,
    }
    if changed then return self:navigate(direction, source) end
    return true
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
        self:use_pointer_selection()
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
        self:use_pointer_selection()
        if self.cancelled_pointer_button == args[3] then self.cancelled_pointer_button = nil end
        local route = self:route_at(self.pointer_x, self.pointer_y)
        local item = route.item
        if args[3] == 1 and item and item.enabled then
            local handle = {key = route.entry.key, id = item.node.id}
            self.focused = item.kind == "text_field" and handle or nil
            self.pressed = {key = handle.key, id = handle.id}
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
            self:queue(item.node.press_started, item.node.id,
                {input_source = "pointer"}, route.entry.key)
            if item.kind == "button" then
                self:queue(item.node.action, item.node.id,
                    {input_source = "pointer"}, route.entry.key)
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
            if item then
                self:queue(item.node.press_ended, item.node.id,
                    {input_source = "pointer"}, entry.key)
            end
            self.pressed, self.pointer_capture = nil, nil
            self:update_hover()
            return true
        end
        return self:route_at(self.pointer_x, self.pointer_y).consumed
    elseif name == "keypressed" then
        local key = args[1]
        local owner = self:keyboard_owner()
        local entry = self.focused and self.layers:get(self.focused.key)
        local item = entry and owner == entry and entry.layout.by_id[self.focused.id]
        if item and item.enabled and item.kind == "text_field"
            and self:field_keypressed(entry, item, key)
        then
            return true
        end
        if key == "tab" then return self:focus_adjacent(self:modifiers().shift and -1 or 1) end
        if key == "up" or key == "down" or key == "left" or key == "right" then
            return self:navigate(key, "keyboard")
        end
        if key == "space" or key == "return" or key == "kpenter" then
            return self:activate_selection("keyboard")
        end
        return owner ~= nil
    elseif name == "keyreleased" then
        local key = args[1]
        if self.keyboard_pressed and (key == "space" or key == "return" or key == "kpenter") then
            if self.keyboard_pressed.semantic then return self:release_selection("keyboard") end
            local pressed = self.keyboard_pressed
            local entry = self.layers:get(pressed.key)
            local item = entry and entry.layout and entry.layout.by_id[pressed.id]
            if item then self:queue(item.node.press_ended, item.node.id,
                {input_source = "keyboard"}, entry.key) end
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

function Context:pointer()
    return self.pointer_x, self.pointer_y
end

function Context:viewport()
    return love.graphics.getDimensions()
end

return Context
