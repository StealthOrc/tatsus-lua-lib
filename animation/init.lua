local MotionValue = require("animation.motion_value")
local Easing = require("animation.easing")
local Value = require("animation.value")

local Animation = {}
Animation.__index = Animation
Animation.easing = Easing
Animation.interpolate = Value.interpolate

function Animation.new()
    return setmetatable({values = {}}, Animation)
end

function Animation:value(initial)
    local value = MotionValue.new(initial)
    self.values[#self.values + 1] = value
    return value
end

function Animation:update(dt)
    for _, value in ipairs(self.values) do value:update(dt) end
end

function Animation:clear()
    self.values = {}
end

function Animation:remove(value)
    for index, candidate in ipairs(self.values) do
        if candidate == value then
            table.remove(self.values, index)
            return true
        end
    end
    return false
end

return setmetatable(Animation, {
    __call = function(_, ...)
        return Animation.new(...)
    end,
})
