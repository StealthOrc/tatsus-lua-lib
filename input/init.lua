local Bindings = require("input.bindings")

local Input = {}

local function binding(kind, values)
    values = values or {}
    values.kind = kind
    values.__input_binding = true
    return values
end

function Input.key(key)
    return binding("key", {key = assert(key, "key binding requires a key")})
end

function Input.gamepad_button(button)
    return binding("gamepad_button", {button = assert(button, "gamepad button binding requires a button")})
end

function Input.chord(controls)
    assert(type(controls) == "table" and #controls > 0, "chord binding requires controls")
    return binding("chord", {controls = controls})
end

function Input.axis(axis, options)
    options = options or {}
    options.axis = assert(axis, "axis binding requires an axis")
    return binding("axis", options)
end

function Input.axis_button(axis, direction, options)
    options = options or {}
    options.axis = assert(axis, "axis button binding requires an axis")
    options.direction = (direction == "negative" or direction == -1) and -1 or 1
    return binding("axis_button", options)
end

function Input.digital_axis(controls)
    assert(type(controls) == "table", "digital axis binding requires controls")
    return binding("digital_axis", controls)
end

function Input.stick(stick, options)
    options = options or {}
    options.stick = assert(stick, "stick binding requires left or right")
    assert(stick == "left" or stick == "right", "stick binding requires left or right")
    return binding("stick", options)
end

function Input.vector2(controls)
    assert(type(controls) == "table", "vector2 binding requires controls")
    return binding("vector2", controls)
end

function Input.new(config)
    return Bindings.new(config)
end

Input.Bindings = Bindings

return Input
