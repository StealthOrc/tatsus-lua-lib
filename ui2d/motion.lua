local Animation = require("animation")
local Layout = require("ui2d.layout")
local StyleSheet = require("ui2d.style_sheet")

local Motion = {}
Motion.__index = Motion

local function visit(item, body)
    body(item)
    for _, child in ipairs(item.children or {}) do visit(child, body) end
end

function Motion.new()
    return setmetatable({animator = Animation.new(), layers = {}, layer_values = {}, generation = 0}, Motion)
end

function Motion:update(dt)
    self.animator:update(dt)
end

local function transition_options(transition, current, target)
    return {
        duration = math.max(0, transition.duration or 0) * math.abs(target - current),
        ease = transition.ease,
        preserve_speed = true,
    }
end

function Motion:add_layer(entry)
    if not entry.transition then return end
    local progress = self.animator:value(0)
    self.layer_values[entry.key] = progress
    progress:to(1, transition_options(entry.transition, 0, 1))
end

function Motion:enter_layer(entry)
    local progress = self.layer_values[entry.key]
    if not progress then return end
    local current = progress:get()
    progress:to(1, transition_options(entry.transition, current, 1))
end

function Motion:exit_layer(entry)
    local progress = self.layer_values[entry.key]
    if not progress then return false end
    local current = progress:get()
    progress:to(0, transition_options(entry.transition, current, 0))
    return true
end

function Motion:layer_exited(entry)
    local progress = self.layer_values[entry.key]
    return progress and progress:is_settled() and progress:get() <= 0
end

function Motion:channel(entry, item, property, initial)
    local layer = self.layers[entry.key]
    if not layer then
        layer = {}
        self.layers[entry.key] = layer
    end
    local node = layer[item.node.id]
    if not node then
        node = {}
        layer[item.node.id] = node
    end
    local channel = node[property]
    if not channel then
        channel = {value = self.animator:value(initial)}
        node[property] = channel
    end
    channel.seen = self.generation
    return channel.value
end

local function visual_targets(entry, item, layout, context)
    local style = item.style or {}
    local transform = StyleSheet.copy(item.node.transform or style.transform or {})
    local opacity = item.node.opacity
    if opacity == nil then opacity = style.opacity end
    opacity = opacity == nil and 1 or opacity

    local states = StyleSheet.copy(style.states or {})
    StyleSheet.merge(states, item.node.states or {})
    local function apply(name)
        local state = states[name]
        if not state then return end
        if state.transform then StyleSheet.merge(transform, state.transform) end
        if state.opacity ~= nil then opacity = state.opacity end
    end
    if item.enabled == false then
        apply("disabled")
    else
        if context:is_focused(entry, item.node.id) then apply("focused") end
        if context:is_hovered(entry, item.node.id) then apply("hovered") end
        if context:is_pressed(entry, item.node.id) then apply("pressed") end
    end
    return Layout.resolve_visual_transform(item, layout, transform), opacity
end

function Motion:reconcile(entry, layout, context)
    self.generation = self.generation + 1
    local generation = self.generation
    visit(layout.root, function(item)
        local transition = item.node.transition or (item.style and item.style.transition) or {}
        local target_transform, target_opacity = visual_targets(entry, item, layout, context)
        if transition.transform or transition.opacity then
            assert(item.node.id, "a transitioning UI node requires an id")
        end
        if transition.transform then
            local target = target_transform
            local value = self:channel(entry, item, "transform", target)
            value:to(target, transition.transform)
            item.motion_transform = value
        elseif item.node.transform or (item.style and (item.style.transform or item.style.states)) or item.node.states then
            item.animated_transform = target_transform
        end
        if transition.opacity then
            local target = target_opacity
            local value = self:channel(entry, item, "opacity", target)
            value:to(target, transition.opacity)
            item.motion_opacity = value
        elseif item.node.opacity ~= nil or (item.style and (item.style.opacity ~= nil or item.style.states))
            or item.node.states
        then
            item.animated_opacity = target_opacity
        end
    end)

    local layer = self.layers[entry.key]
    if not layer then return end
    for node_id, channels in pairs(layer) do
        for property, channel in pairs(channels) do
            if channel.seen ~= generation then
                self.animator:remove(channel.value)
                channels[property] = nil
            end
        end
        if next(channels) == nil then layer[node_id] = nil end
    end
end

function Motion:apply(entry)
    if not entry.layout then return end
    visit(entry.layout.root, function(item)
        if item.motion_transform then item.animated_transform = item.motion_transform:get() end
        if item.motion_opacity then item.animated_opacity = item.motion_opacity:get() end
    end)
    local progress = self.layer_values[entry.key]
    if progress then
        local transition = entry.transition
        local from = transition.from or {}
        local to = transition.to or {}
        local from_transform = Layout.resolve_visual_transform(entry.layout.root, entry.layout, from.transform or {})
        local to_transform = Layout.resolve_visual_transform(entry.layout.root, entry.layout, to.transform or {})
        local amount = progress:get()
        entry.layout.layer_visual_transform = Animation.interpolate(from_transform, to_transform, amount)
        entry.layout.layer_opacity = (from.opacity == nil and 1 or from.opacity)
            + ((to.opacity == nil and 1 or to.opacity) - (from.opacity == nil and 1 or from.opacity)) * amount
    else
        entry.layout.layer_visual_transform = nil
        entry.layout.layer_opacity = 1
    end
    Layout.refresh_visuals(entry.layout)
end

function Motion:remove_layer(key)
    local layer = self.layers[key]
    if layer then
        for _, channels in pairs(layer) do
            for _, channel in pairs(channels) do self.animator:remove(channel.value) end
        end
    end
    self.layers[key] = nil
    local progress = self.layer_values[key]
    if progress then self.animator:remove(progress) end
    self.layer_values[key] = nil
end

return Motion
