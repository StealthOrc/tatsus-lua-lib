local StyleSheet = require("ui2d.core.style_sheet")
local FontCache = require("ui2d.core.font_cache")
local TextField = require("ui2d.components.text_field")
local Slider = require("ui2d.components.slider")
local Select = require("ui2d.components.select")
local MediaCache = require("ui2d.core.media_cache")
local Layout = require("ui2d.core.layout")
local Renderer = require("ui2d.core.renderer")
local LayerStack = require("ui2d.core.layer_stack")
local Motion = require("ui2d.core.motion")
local Shader = require("ui2d.core.shader")
local Navigation = require("ui2d.core.navigation")
local Gestures = require("ui2d.core.gestures")
local InputRouter = require("ui2d.core.input_router")
local Transform = require("ui2d.core.transform")

local Context = {}
Context.__index = Context

local function same_handle(handle, key, id)
    return handle and handle.key == key and handle.id == id
end

local function input_source_kind(source)
    if type(source) == "table" then return source.kind or "navigation" end
    return source or "navigation"
end

function Context.new(config)
    config = config or {}
    local input_mode_policy = config.input_mode or "automatic"
    assert(input_mode_policy == "automatic" or input_mode_policy == "simultaneous",
        "ui2d input_mode must be automatic or simultaneous")
    local initial_input_mode = config.initial_input_mode or "pointer"
    local styles = config.styles
    if getmetatable(styles) ~= StyleSheet then styles = StyleSheet.new(styles or {}) end
    local media = MediaCache.new(config.images, config.icons)
    local shaders = Shader.Cache.new(config.shaders)
    return setmetatable({
        styles = styles,
        icons = media,
        media = media,
        shaders = shaders,
        fonts = FontCache.new(styles),
        renderer = Renderer.new(styles, media, shaders),
        dispatch = config.dispatch,
        navigation_options = type(config.navigation) == "table" and config.navigation or {},
        navigation_enabled = config.navigation ~= false,
        layers = LayerStack.new(config.layers),
        motion = Motion.new(),
        editors = {},
        scrolls = {},
        selects = {},
        actions = {},
        time = 0,
        pointer_x = 0,
        pointer_y = 0,
        selections = {},
        selection_mode = initial_input_mode,
        navigation_input = {x = 0, y = 0},
        input_mode_policy = input_mode_policy,
        initial_input_mode = initial_input_mode,
        viewport_provider = config.viewport,
    }, Context)
end

function Context:show(view, options)
    local cancelled_pointer_button = self.pointer_capture and 1 or self.cancelled_pointer_button
    self.layers:clear()
    self.motion = Motion.new()
    self.editors = {}
    self.scrolls = {}
    self.selects = {}
    self.hovered, self.pressed, self.focused = nil, nil, nil
    self.selections = {}
    self.selection_mode = self.initial_input_mode
    self.navigation_input = {x = 0, y = 0}
    self.pointer_capture, self.keyboard_pressed, self.hold, self.semantic_drag = nil, nil, nil, nil
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
        existing.style_overrides = options.styles or existing.style_overrides
        self.motion:enter_layer(existing)
        return existing.key
    elseif existing then
        existing.view = view
        if options.model ~= nil then existing.model = options.model end
        if options.styles ~= nil then existing.style_overrides = options.styles end
        return existing.key
    end
    local entry = self.layers:push(view, options)
    self.editors[entry.key] = self.editors[entry.key] or {}
    self.scrolls[entry.key] = self.scrolls[entry.key] or {}
    self.selects[entry.key] = self.selects[entry.key] or {}
    self.motion:add_layer(entry)
    return entry.key
end

function Context:discard(key)
    local entry = self.layers:remove(key)
    if not entry then return false end
    self.editors[key] = nil
    self.scrolls[key] = nil
    self.selects[key] = nil
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
    if self.hold and self.hold.key == key then self:cancel_hold("layer_removed") end
    if self.semantic_drag and self.semantic_drag.key == key then
        self:end_semantic_drag("layer_removed")
    end
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
        if self.hold and self.hold.key == key then self:cancel_hold("layer_removed") end
        if self.semantic_drag and self.semantic_drag.key == key then
            self:end_semantic_drag("layer_removed")
        end
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
    return TextField.editor_for(editors, node,
        same_handle(self.focused, entry.key, node.id))
end

function Context:scroll_for(entry, node)
    local view_scrolls = self.scrolls[entry.key]
    local state = view_scrolls[node.id]
    if not state then
        state = {x = 0, y = 0}
        view_scrolls[node.id] = state
    end
    return state
end

function Context:select_for(entry, node)
    local view_selects = self.selects[entry.key]
    local state = view_selects[node.id]
    if not state then
        state = {open = node.open == true}
        view_selects[node.id] = state
    end
    return state
end

function Context:rebuild()
    local width, height = self:viewport()
    for _, entry in ipairs(self.layers.entries) do
        local root = entry.view.build(self:model_value(entry) or {})
        local styles = self.styles
        if entry.view.styles then styles = styles:with(entry.view.styles) end
        if entry.style_overrides then styles = styles:with(entry.style_overrides) end
        entry.styles = styles
        entry.layout = Layout.build(root, width, height, {
            styles = styles,
            fonts = self.fonts:with_styles(styles),
            icons = self.icons,
            media = self.media,
            editor_for = function(node) return self:editor_for(entry, node) end,
            scroll_for = function(node)
                return self:scroll_for(entry, node)
            end,
            select_for = function(node)
                return self:select_for(entry, node)
            end,
            scale = self.styles:viewport_scale(width, height),
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
            local first = entry and entry.layout and Navigation.first(
                entry.layout,
                self:navigation_options_for(entry).initial
            )
            self.selections[key] = first and {key = key, id = first.node.id} or nil
        end
    end
    for _, entry in ipairs(self.layers.entries) do
        if entry.navigation ~= "pass" and not self.selections[entry.key] and entry.layout then
            local first = Navigation.first(
                entry.layout,
                self:navigation_options_for(entry).initial
            )
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
    if type(action) == "table" and action.__ui2d_select then
        return Select.handle(self, action, extra, view_key)
    end
    local value = Gestures.action_value(action, source_id, extra, view_key)
    if value then self.actions[#self.actions + 1] = value end
end

function Context:take_actions()
    local actions = self.actions
    self.actions = {}
    return actions
end

function Context:start_hold(entry, item, source)
    local options = Gestures.hold_options(item.node)
    if not options then return false end
    local duration = tonumber(options.duration or options.seconds or 1)
    assert(duration and duration > 0, "a button hold duration must be greater than zero")
    if self.hold then
        if same_handle(self.hold, entry.key, item.node.id) then return true end
        self:cancel_hold("replaced")
    end
    self.hold = {
        key = entry.key,
        id = item.node.id,
        elapsed = 0,
        duration = duration,
        progress = 0,
        completed = false,
        source = source,
        options = options,
        action = options.completed or item.node.action,
    }
    self:queue(options.started, item.node.id, {
        progress = 0,
        elapsed = 0,
        duration = duration,
        input_source = source,
    }, entry.key)
    return true
end

function Context:cancel_hold(reason)
    local hold = self.hold
    if not hold then return false end
    self.hold = nil
    if not hold.completed then
        self:queue(hold.options.cancelled, hold.id, {
            progress = hold.progress,
            elapsed = hold.elapsed,
            duration = hold.duration,
            input_source = hold.source,
            reason = reason or "cancelled",
        }, hold.key)
    end
    return true
end

function Context:release_hold(key, id)
    if not same_handle(self.hold, key, id) then return false end
    return self:cancel_hold("released")
end

function Context:update_hold(dt)
    local hold = self.hold
    if not hold or hold.completed then return end
    local entry = self.layers:get(hold.key)
    local item = entry and entry.layout and entry.layout.by_id[hold.id]
    if not item or not item.enabled then
        self:cancel_hold("unavailable")
        self.pressed = nil
        return
    end
    hold.elapsed = math.min(hold.duration, hold.elapsed + math.max(0, dt or 0))
    hold.progress = hold.elapsed / hold.duration
    self:queue(hold.options.progress, hold.id, {
        progress = hold.progress,
        elapsed = hold.elapsed,
        duration = hold.duration,
        input_source = hold.source,
    }, hold.key)
    if hold.progress >= 1 then
        hold.completed = true
        self:queue(hold.action, hold.id, {
            progress = 1,
            elapsed = hold.duration,
            duration = hold.duration,
            input_source = hold.source,
        }, hold.key)
    end
end

function Context:hold_progress(id, view_key)
    local hold = self.hold
    if not hold or hold.id ~= id or (view_key and hold.key ~= view_key) then return 0 end
    return hold.progress
end

function Context:is_holding(entry, id)
    return same_handle(self.hold, entry.key, id)
end

function Context:start_semantic_drag(entry, item, source)
    local options = Gestures.semantic_drag_options(item.node)
    if not options then return false end
    if self.semantic_drag then
        if same_handle(self.semantic_drag, entry.key, item.node.id) then return true end
        self:end_semantic_drag("replaced")
    end
    local rect = item.visual_rect or item.rect
    local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
    local deadzone = math.max(0, math.min(0.95, tonumber(options.deadzone) or 0.15))
    local speed = math.max(0, tonumber(options.speed) or 640) * (item.layout_scale or 1)
    local mode = options.mode or "continuous"
    assert(mode == "continuous" or mode == "flick",
        "semantic_drag mode must be continuous or flick")
    local axis = options.axis
    assert(axis == nil or axis == "horizontal" or axis == "vertical",
        "semantic_drag axis must be horizontal or vertical")
    self.semantic_drag = {
        key = entry.key,
        id = item.node.id,
        start_x = x,
        start_y = y,
        last_x = x,
        last_y = y,
        x = x,
        y = y,
        input_x = 0,
        input_y = 0,
        speed = speed,
        mode = mode,
        max_distance = math.max(0, tonumber(options.max_distance) or 96) * (item.layout_scale or 1),
        response = math.max(0, tonumber(options.response) or 18),
        flick_threshold = math.max(0, tonumber(options.flick_threshold) or 8),
        deadzone = deadzone,
        axis = axis,
        source = source,
        offset_x = 0,
        offset_y = 0,
        velocity_x = 0,
        velocity_y = 0,
        flick_x = 0,
        flick_y = 0,
        raw_input_x = 0,
        raw_input_y = 0,
        input_time = love.timer.getTime(),
    }
    self.navigation_input = {x = 0, y = 0}
    self:queue(item.node.drag_started, item.node.id, {
        x = x,
        y = y,
        dx = 0,
        dy = 0,
        total_dx = 0,
        total_dy = 0,
        input_source = source,
        semantic = true,
        mode = mode,
        velocity_x = 0,
        velocity_y = 0,
        flick_x = 0,
        flick_y = 0,
        flicked = false,
    }, entry.key)
    return true
end

function Context:set_semantic_drag_input(event, source)
    local capture = self.semantic_drag
    if not capture then return false end
    local value = event.value or event
    local x, y = value.x or 0, value.y or 0
    if event.direction then x, y = Gestures.direction_vector(event.direction) end
    if event.phase == "released" then x, y = 0, 0 end
    x = Gestures.apply_deadzone(x, capture.deadzone)
    y = Gestures.apply_deadzone(y, capture.deadzone)
    if capture.axis == "horizontal" then y = 0
    elseif capture.axis == "vertical" then x = 0 end
    local now = love.timer.getTime()
    local elapsed = math.max(1 / 240, now - capture.input_time)
    capture.flick_x = Gestures.retain_flick(capture.flick_x,
        Gestures.outward_velocity(x, capture.raw_input_x, elapsed))
    capture.flick_y = Gestures.retain_flick(capture.flick_y,
        Gestures.outward_velocity(y, capture.raw_input_y, elapsed))
    capture.raw_input_x, capture.raw_input_y = x, y
    capture.input_time = now
    capture.input_x, capture.input_y = x, y
    capture.source = source or capture.source
    self.navigation_input = {x = x, y = y}
    if capture.mode == "flick" and x == 0 and y == 0
        and math.max(math.abs(capture.flick_x), math.abs(capture.flick_y))
            >= capture.flick_threshold
    then
        return self:end_semantic_drag("flicked")
    end
    return true
end

function Context:update_semantic_drag(dt)
    local capture = self.semantic_drag
    if not capture then return end
    local entry = self.layers:get(capture.key)
    local item = entry and entry.layout and entry.layout.by_id[capture.id]
    if not item or not item.enabled then
        self:end_semantic_drag("unavailable")
        self.pressed = nil
        return
    end
    dt = math.max(0, dt or 0)
    if dt == 0 then return end
    local dx, dy
    if capture.mode == "flick" then
        local blend = 1 - math.exp(-capture.response * dt)
        local target_x = capture.input_x * capture.max_distance
        local target_y = capture.input_y * capture.max_distance
        local next_x = capture.offset_x + (target_x - capture.offset_x) * blend
        local next_y = capture.offset_y + (target_y - capture.offset_y) * blend
        dx, dy = next_x - capture.offset_x, next_y - capture.offset_y
        capture.offset_x, capture.offset_y = next_x, next_y
    else
        dx = capture.input_x * capture.speed * dt
        dy = capture.input_y * capture.speed * dt
    end
    capture.velocity_x, capture.velocity_y = dx / dt, dy / dt
    if dx == 0 and dy == 0 then return end
    capture.x, capture.y = capture.x + dx, capture.y + dy
    local values = Gestures.semantic_drag_values(capture, capture.x, capture.y)
    self:queue(item.node.dragged, item.node.id, values, entry.key)
    capture.last_x, capture.last_y = capture.x, capture.y
end

function Context:end_semantic_drag(reason)
    local capture = self.semantic_drag
    if not capture then return false end
    self.semantic_drag = nil
    local entry = self.layers:get(capture.key)
    local item = entry and entry.layout and entry.layout.by_id[capture.id]
    if item then
        local values = Gestures.semantic_drag_values(capture, capture.x, capture.y)
        values.reason = reason
        values.cancelled = reason ~= nil and reason ~= "released" and reason ~= "flicked"
        self:queue(item.node.drag_ended, item.node.id, values, entry.key)
    end
    local direction = Navigation.direction(capture.input_x, capture.input_y, 0.5)
    self.navigation_input = {
        x = capture.input_x,
        y = capture.input_y,
        drag_latched = direction ~= nil,
    }
    return true
end

function Context:update(dt)
    self.time = self.time + (dt or 0)
    self:update_hold(dt or 0)
    self:update_semantic_drag(dt or 0)
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
                if Gestures.point_in_item(region.item, x, y) then
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

local function point_in_rect(rect, x, y)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function blocks_lower_pointer_layer(entry, x, y)
    local layout = entry.layout
    if not layout then return false end
    if layout.modal or entry.pointer ~= "pass" then return true end
    for index = #layout.hit_regions, 1, -1 do
        if Gestures.point_in_item(layout.hit_regions[index].item, x, y) then
            return true
        end
    end
    return false
end

function Context:scroll_at(x, y, delta_x, delta_y)
    for layer_index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[layer_index]
        local layout = entry.layout
        for index = layout and #layout.scrollable or 0, 1, -1 do
            local item = layout.scrollable[index]
            local options = type(item.node.scroll) == "table"
                and item.node.scroll
                or {}
            if options.wheel ~= false and Gestures.point_in_item(
                item,
                x,
                y
            ) then
                local speed = tonumber(options.wheel_speed) or 42
                local state = item.scroll_state
                local previous_x, previous_y = state.x, state.y
                if item.scroll_max_x > 0 then
                    state.x = math.max(0, math.min(
                        item.scroll_max_x,
                        state.x - (delta_x or 0) * speed
                    ))
                end
                if item.scroll_max_y > 0 then
                    state.y = math.max(0, math.min(
                        item.scroll_max_y,
                        state.y - (delta_y or 0) * speed
                    ))
                end
                if state.x ~= previous_x or state.y ~= previous_y then
                    self:rebuild()
                end
                return true
            end
        end
        if blocks_lower_pointer_layer(entry, x, y) then return false end
    end
    return false
end

function Context:scrollbar_at(x, y)
    for layer_index = #self.layers.entries, 1, -1 do
        local entry = self.layers.entries[layer_index]
        local layout = entry.layout
        for index = layout and #layout.scrollable or 0, 1, -1 do
            local item = layout.scrollable[index]
            local options = type(item.node.scroll) == "table"
                and item.node.scroll
                or {}
            if options.drag ~= false
                and Gestures.point_in_item(item, x, y)
            then
                for _, axis in ipairs({"vertical", "horizontal"}) do
                    local scrollbar = item.scrollbars
                        and item.scrollbars[axis]
                    if scrollbar and point_in_rect(
                        scrollbar.visual_track,
                        x,
                        y
                    ) then
                        return entry, item, axis
                    end
                end
            end
        end
        if blocks_lower_pointer_layer(entry, x, y) then return nil end
    end
end

function Context:set_scrollbar_pointer(
    item,
    axis,
    pointer_x,
    pointer_y,
    offset
)
    local scrollbar = item.scrollbars and item.scrollbars[axis]
    if not scrollbar then return false end
    local local_x, local_y = Transform.unapply(
        item.world_transform,
        pointer_x,
        pointer_y
    )
    if not local_x then return false end
    local vertical = axis == "vertical"
    local track, thumb = scrollbar.track, scrollbar.thumb
    local track_length = vertical and track.h or track.w
    local thumb_length = vertical and thumb.h or thumb.w
    local pointer = vertical and local_y or local_x
    local origin = vertical and track.y or track.x
    local maximum = vertical and item.scroll_max_y or item.scroll_max_x
    local position = pointer - origin - (offset or thumb_length * 0.5)
    local value = maximum
        * math.max(
            0,
            math.min(
                1,
                position / math.max(1, track_length - thumb_length)
            )
        )
    item.scroll_state[vertical and "y" or "x"] = value
    self:rebuild()
    return true
end

function Context:ensure_visible(entry, item)
    local current = item.parent
    local changed = false
    while current do
        if current.scroll_state and current.scroll_max_y > 0 then
            local viewport = current.scroll_viewport_rect
                or current.rect
            local top = viewport.y
            local bottom = viewport.y + viewport.h
            if item.rect.y < top then
                current.scroll_state.y = math.max(
                    0,
                    current.scroll_state.y - (top - item.rect.y)
                )
                changed = true
            elseif item.rect.y + item.rect.h > bottom then
                current.scroll_state.y = math.min(
                    current.scroll_max_y,
                    current.scroll_state.y
                        + (item.rect.y + item.rect.h - bottom)
                )
                changed = true
            end
        end
        if current.scroll_state and current.scroll_max_x > 0 then
            local viewport = current.scroll_viewport_rect
                or current.rect
            local left = viewport.x
            local right = viewport.x + viewport.w
            if item.rect.x < left then
                current.scroll_state.x = math.max(
                    0,
                    current.scroll_state.x - (left - item.rect.x)
                )
                changed = true
            elseif item.rect.x + item.rect.w > right then
                current.scroll_state.x = math.min(
                    current.scroll_max_x,
                    current.scroll_state.x
                        + (item.rect.x + item.rect.w - right)
                )
                changed = true
            end
        end
        current = current.parent
    end
    if changed then self:rebuild() end
end

function Context:update_hover()
    if self.input_mode_policy == "automatic" and self.selection_mode ~= "pointer" then
        if self.hovered then
            local previous = self.hovered
            self.hovered = nil
            local entry = self.layers:get(previous.key)
            local item = entry and entry.layout and entry.layout.by_id[previous.id]
            if item then self:queue(item.node.hover_leave, previous.id, nil, previous.key) end
        end
        return
    end
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
    if self.input_mode_policy == "automatic" and self.selection_mode ~= "pointer" then return false end
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
    if self.hold and input_source_kind(self.hold.source) ~= input_source_kind(source) then
        self:cancel_hold("input_mode_changed")
        self.pressed = nil
    end
    if self.semantic_drag
        and input_source_kind(self.semantic_drag.source) ~= input_source_kind(source)
    then
        self:end_semantic_drag("input_mode_changed")
        self.pressed = nil
    end
    if self.input_mode_policy == "automatic" and self.hovered then
        local hovered = self.hovered
        self.hovered = nil
        local hovered_entry = self.layers:get(hovered.key)
        local hovered_item = hovered_entry and hovered_entry.layout
            and hovered_entry.layout.by_id[hovered.id]
        if hovered_item then
            self:queue(hovered_item.node.hover_leave, hovered.id,
                {input_source = source}, hovered.key)
        end
    end
    if previous and item and previous.id == item.node.id then
        previous.source = source or previous.source
        self.selection_mode = input_source_kind(source or self.selection_mode)
        if not was_active then
            self:queue(item.node.select_enter, item.node.id,
                {selection_source = source}, entry.key)
        end
        return true
    end
    if self.hold and self.hold.key == entry.key
        and (not item or self.hold.id ~= item.node.id)
    then
        self:cancel_hold("selection_changed")
        self.pressed = nil
    end
    if self.semantic_drag and self.semantic_drag.key == entry.key
        and (not item or self.semantic_drag.id ~= item.node.id)
    then
        self:end_semantic_drag("selection_changed")
        self.pressed = nil
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
        self:ensure_visible(entry, item)
    end
    return item ~= nil
end

function Context:use_pointer_selection()
    if self.selection_mode == "pointer" then return end
    if self.hold and input_source_kind(self.hold.source) ~= "pointer" then
        self:cancel_hold("input_mode_changed")
        self.pressed = nil
    end
    if self.semantic_drag and input_source_kind(self.semantic_drag.source) ~= "pointer" then
        self:end_semantic_drag("input_mode_changed")
        self.pressed = nil
    end
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

function Context:input_mode()
    return self.selection_mode
end

function Context:navigate(direction, source)
    local entry = self:navigation_owner()
    local layout = entry and entry.layout
    if not layout or #(layout.navigable or {}) == 0 then return false end
    local selection = self:navigation_selection(entry)
    local current = selection and layout.by_id[selection.id]
    if current and current.kind == "slider" and current.enabled then
        local value = Slider.adjusted_value(current.node, direction)
        if value ~= nil then
            self:queue(
                Slider.changed_action(current.node, value),
                current.node.id,
                {input_source = source},
                entry.key
            )
            return true
        end
    end
    local options = self:navigation_options_for(entry)
    local request = {
        context = self,
        view = entry.key,
        source = source,
        selected = selection and selection.id or nil,
    }
    local target = Navigation.move(layout, selection and selection.id, direction, options, request)
    if target then return self:set_navigation_selection(entry, target, source or "navigation") end
    current = selection and layout.by_id[selection.id]
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
    if item.kind == "slider" then return true end
    if item.kind ~= "button" then return false end
    self.pressed = {key = entry.key, id = item.node.id}
    self.keyboard_pressed = {key = entry.key, id = item.node.id, semantic = true}
    self.keyboard_pressed.semantic_drag = self:start_semantic_drag(entry, item, source)
    self:queue(item.node.press_started, item.node.id, {input_source = source}, entry.key)
    if not self:start_hold(entry, item, source) then
        self:queue(item.node.action, item.node.id, {input_source = source}, entry.key)
    end
    return true
end

function Context:change_slider(entry, item, x, y, source)
    local value = Slider.value_at(item, x, y)
    self:queue(
        Slider.changed_action(item.node, value),
        item.node.id,
        {input_source = source},
        entry.key
    )
    return true
end

function Context:accept_selection(source)
    local source_kind = input_source_kind(source)
    if self.input_mode_policy == "automatic"
        and source_kind ~= "pointer"
        and self.selection_mode ~= source_kind
    then
        local entry = self:navigation_owner()
        local layout = entry and entry.layout
        if not layout or #(layout.navigable or {}) == 0 then return false end
        local selection = self:navigation_selection(entry)
        local item = selection and layout.by_id[selection.id]
        if not item or not item.enabled or not item.navigation_enabled then
            item = Navigation.first(layout, self:navigation_options_for(entry).initial)
        end
        return item and self:set_navigation_selection(entry, item, source) or false
    end
    return self:activate_selection(source)
end

function Context:release_selection(source)
    local pressed = self.keyboard_pressed
    if not pressed or not pressed.semantic then return false end
    local entry = self.layers:get(pressed.key)
    local item = entry and entry.layout and entry.layout.by_id[pressed.id]
    self:release_hold(pressed.key, pressed.id)
    if same_handle(self.semantic_drag, pressed.key, pressed.id) then
        self:end_semantic_drag("released")
    end
    if item then self:queue(item.node.press_ended, item.node.id, {input_source = source}, entry.key) end
    self.keyboard_pressed, self.pressed = nil, nil
    return true
end

function Context:input(event)
    return InputRouter.input(self, event)
end

function Context:field_keypressed(entry, item, key)
    local result = TextField.keypressed(item.editor, key, self:modifiers())
    if not result.handled then return false end
    if result.changed then self:emit_editor_change(entry, item) end
    if result.submit then
        self:queue(item.node.submit, item.node.id, {value = item.editor:value()}, entry.key)
    end
    if result.blur then self.focused = nil end
    return true
end

function Context:event(name, ...)
    return InputRouter.event(self, name, ...)
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
    if self.viewport_provider then
        return self.viewport_provider()
    end
    return love.graphics.getDimensions()
end

return Context
