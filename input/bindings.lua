local Bindings = {}
Bindings.__index = Bindings

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function device_id(joystick)
    if type(joystick) == "table" or type(joystick) == "userdata" then
        local ok, value = pcall(function() return joystick:getID() end)
        if ok then return value end
    end
    return tostring(joystick or "gamepad")
end

local function device_key(scheme, id)
    return tostring(scheme) .. ":" .. tostring(id or scheme)
end

local function is_binding(value)
    return type(value) == "table" and value.__input_binding == true
end

local function bindings_list(value)
    if value == nil then return {} end
    if is_binding(value) or type(value) == "string" then return {value} end
    assert(type(value) == "table", "action bindings must be a binding or a list of bindings")
    return value
end

local function normalize_control(control, scheme)
    if is_binding(control) then return control end
    if type(control) == "string" then
        if scheme == "gamepad" then
            return {kind = "gamepad_button", button = control, __input_binding = true}
        end
        return {kind = "key", key = control, __input_binding = true}
    end
    error("invalid input control")
end

local function modifier_down(keys, name)
    if name == "ctrl" then return keys.lctrl or keys.rctrl end
    if name == "shift" then return keys.lshift or keys.rshift end
    if name == "alt" then return keys.lalt or keys.ralt end
    if name == "gui" or name == "command" then return keys.lgui or keys.rgui end
    return keys[name] == true
end

local function deadzone(value, amount)
    amount = math.max(0, math.min(0.95, amount or 0.2))
    local magnitude = math.abs(value or 0)
    if magnitude <= amount then return 0 end
    local scaled = (magnitude - amount) / (1 - amount)
    return value < 0 and -scaled or scaled
end

local function control_value(self, control, scheme, id)
    if control == nil then return 0 end
    control = normalize_control(control, scheme)
    local kind = control.kind
    if kind == "key" then return modifier_down(self.keys, control.key) and 1 or 0 end
    local gamepad = self.gamepads[id] or {buttons = {}, axes = {}}
    if kind == "gamepad_button" then return gamepad.buttons[control.button] and 1 or 0 end
    if kind == "axis" then
        return deadzone(gamepad.axes[control.axis] or 0, control.deadzone) * (control.scale or 1)
    end
    if kind == "axis_button" then
        local value = (gamepad.axes[control.axis] or 0) * (control.direction or 1)
        return value >= (control.threshold or 0.55) and 1 or 0
    end
    if kind == "chord" then
        for _, child in ipairs(control.controls or {}) do
            if control_value(self, child, scheme, id) <= 0.5 then return 0 end
        end
        return 1
    end
    return 0
end

local function evaluate(self, spec, scheme, id)
    spec = normalize_control(spec, scheme)
    if spec.kind == "digital_axis" then
        return control_value(self, spec.positive, scheme, id)
            - control_value(self, spec.negative, scheme, id)
    elseif spec.kind == "stick" then
        local prefix = spec.stick == "right" and "right" or "left"
        return {
            x = deadzone((self.gamepads[id] and self.gamepads[id].axes[prefix .. "x"]) or 0,
                spec.deadzone) * (spec.scale_x or 1),
            y = deadzone((self.gamepads[id] and self.gamepads[id].axes[prefix .. "y"]) or 0,
                spec.deadzone) * (spec.scale_y or 1),
        }
    elseif spec.kind == "vector2" then
        return {
            x = control_value(self, spec.right, scheme, id) - control_value(self, spec.left, scheme, id),
            y = control_value(self, spec.down, scheme, id) - control_value(self, spec.up, scheme, id),
        }
    end
    return control_value(self, spec, scheme, id)
end

local function same_value(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) == "table" then
        return math.abs((left.x or 0) - (right.x or 0)) < 0.0001
            and math.abs((left.y or 0) - (right.y or 0)) < 0.0001
    end
    return left == right or math.abs((left or 0) - (right or 0)) < 0.0001
end

local function value_active(value)
    if type(value) == "table" then
        return math.max(math.abs(value.x or 0), math.abs(value.y or 0)) > 0.15
    end
    return math.abs(value or 0) > 0.15
end

local function combine(kind, values)
    if kind == "button" then
        for _, value in ipairs(values) do if value > 0.5 then return 1 end end
        return 0
    elseif kind == "axis2d" then
        local best, magnitude = {x = 0, y = 0}, -1
        for _, value in ipairs(values) do
            if type(value) == "table" then
                local current = (value.x or 0) ^ 2 + (value.y or 0) ^ 2
                if current > magnitude then best, magnitude = value, current end
            end
        end
        return {x = math.max(-1, math.min(1, best.x or 0)), y = math.max(-1, math.min(1, best.y or 0))}
    end
    local best = 0
    for _, value in ipairs(values) do
        if type(value) == "number" and math.abs(value) > math.abs(best) then best = value end
    end
    return math.max(-1, math.min(1, best))
end

function Bindings.new(config)
    config = config or {}
    return setmetatable({
        actions = copy(config.actions or {}),
        bindings = copy(config.bindings or {}),
        dispatch = config.dispatch,
        keys = {},
        gamepads = {},
        values = {},
        queue = {},
        active = {kind = config.initial_device or "keyboard", id = config.initial_device or "keyboard"},
        capture_threshold = config.capture_threshold or 0.65,
    }, Bindings)
end

function Bindings:queue_action(action, phase, value, scheme, id)
    local event = {
        action = action,
        phase = phase,
        value = value,
        source = {kind = scheme, id = id},
    }
    self.queue[#self.queue + 1] = event
    if value_active(value) then self.active = {kind = scheme, id = id} end
end

function Bindings:evaluate_action(action, scheme, id)
    local definitions = self.bindings[scheme] or {}
    local specs = bindings_list(definitions[action])
    local values = {}
    for _, spec in ipairs(specs) do values[#values + 1] = evaluate(self, spec, scheme, id) end
    local kind = (self.actions[action] and self.actions[action].kind) or "button"
    return combine(kind, values), kind
end

function Bindings:refresh(scheme, id)
    local key = device_key(scheme, id)
    self.values[key] = self.values[key] or {}
    for action in pairs(self.actions) do
        local value, kind = self:evaluate_action(action, scheme, id)
        local previous = self.values[key][action]
        if previous == nil then previous = kind == "axis2d" and {x = 0, y = 0} or 0 end
        if not same_value(previous, value) then
            local phase = "changed"
            if kind == "button" then phase = value > 0.5 and "pressed" or "released" end
            self.values[key][action] = copy(value)
            self:queue_action(action, phase, value, scheme, id)
        end
    end
end

local modifier_keys = {lctrl = true, rctrl = true, lshift = true, rshift = true,
    lalt = true, ralt = true, lgui = true, rgui = true}

function Bindings:captured(spec)
    local capture = self.capture_state
    if not capture then return false end
    self:set(capture.action, capture.scheme, spec, capture.append)
    self.capture_state = nil
    return true
end

function Bindings:capture_event(name, ...)
    local capture = self.capture_state
    if not capture then return false end
    local args = {...}
    if capture.scheme == "keyboard" and name == "keypressed" then
        local key = args[1]
        if modifier_keys[key] then return true end
        local controls = {}
        if modifier_down(self.keys, "ctrl") then controls[#controls + 1] = "ctrl" end
        if modifier_down(self.keys, "alt") then controls[#controls + 1] = "alt" end
        if modifier_down(self.keys, "shift") then controls[#controls + 1] = "shift" end
        if modifier_down(self.keys, "gui") then controls[#controls + 1] = "gui" end
        controls[#controls + 1] = key
        if #controls == 1 then
            return self:captured({kind = "key", key = key, __input_binding = true})
        end
        return self:captured({kind = "chord", controls = controls, __input_binding = true})
    elseif capture.scheme == "gamepad" and name == "gamepadpressed" then
        return self:captured({kind = "gamepad_button", button = args[2], __input_binding = true})
    elseif capture.scheme == "gamepad" and name == "gamepadaxis"
        and math.abs(args[3] or 0) >= self.capture_threshold
    then
        local axis = args[2]
        local kind = self.actions[capture.action] and self.actions[capture.action].kind or "button"
        if kind == "axis2d" and (axis:match("^left[xy]$") or axis:match("^right[xy]$")) then
            return self:captured({kind = "stick", stick = axis:sub(1, -2), __input_binding = true})
        elseif kind == "button" then
            return self:captured({kind = "axis_button", axis = axis,
                direction = args[3] < 0 and -1 or 1, __input_binding = true})
        end
        return self:captured({kind = "axis", axis = axis, __input_binding = true})
    end
    return false
end

function Bindings:event(name, ...)
    local args = {...}
    if name == "keypressed" then
        self.keys[args[1]] = true
        self.active = {kind = "keyboard", id = "keyboard"}
        if self:capture_event(name, ...) then return true end
        self:refresh("keyboard", "keyboard")
        return true
    elseif name == "keyreleased" then
        self.keys[args[1]] = false
        self:refresh("keyboard", "keyboard")
        return true
    elseif name == "gamepadpressed" or name == "gamepadreleased" then
        local id = device_id(args[1])
        self.gamepads[id] = self.gamepads[id] or {buttons = {}, axes = {}}
        self.gamepads[id].buttons[args[2]] = name == "gamepadpressed"
        if name == "gamepadpressed" then self.active = {kind = "gamepad", id = id} end
        if name == "gamepadpressed" and self:capture_event(name, ...) then return true end
        self:refresh("gamepad", id)
        return true
    elseif name == "gamepadaxis" then
        local id = device_id(args[1])
        self.gamepads[id] = self.gamepads[id] or {buttons = {}, axes = {}}
        self.gamepads[id].axes[args[2]] = args[3]
        if math.abs(args[3] or 0) > 0.2 then self.active = {kind = "gamepad", id = id} end
        if self:capture_event(name, ...) then return true end
        self:refresh("gamepad", id)
        return true
    elseif name == "joystickremoved" then
        local id = device_id(args[1])
        self.gamepads[id] = nil
        self.values[device_key("gamepad", id)] = nil
        return true
    end
    return false
end

function Bindings:update()
    if not self.dispatch then return end
    for _, event in ipairs(self:take_actions()) do self.dispatch(event) end
end

function Bindings:take_actions()
    local result = self.queue
    self.queue = {}
    return result
end

function Bindings:active_device()
    return copy(self.active)
end

function Bindings:prompts(action, scheme)
    local definitions = self.bindings[scheme or self.active.kind] or {}
    return copy(bindings_list(definitions[action]))
end

function Bindings:set(action, scheme, value, append)
    assert(self.actions[action], "unknown input action: " .. tostring(action))
    assert(scheme == "keyboard" or scheme == "gamepad", "binding scheme must be keyboard or gamepad")
    self.bindings[scheme] = self.bindings[scheme] or {}
    if append then
        local current = bindings_list(self.bindings[scheme][action])
        current[#current + 1] = copy(value)
        self.bindings[scheme][action] = current
    else
        self.bindings[scheme][action] = copy(value)
    end
    return self
end

function Bindings:begin_capture(action, scheme, options)
    assert(self.actions[action], "unknown input action: " .. tostring(action))
    assert(scheme == "keyboard" or scheme == "gamepad", "binding scheme must be keyboard or gamepad")
    options = options or {}
    self.capture_state = {action = action, scheme = scheme, append = options.append == true}
    return self
end

function Bindings:cancel_capture()
    self.capture_state = nil
end

function Bindings:capturing()
    return self.capture_state and copy(self.capture_state) or nil
end

function Bindings:export()
    return copy(self.bindings)
end

return Bindings
