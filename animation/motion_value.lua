local Easing = require("animation.easing")
local Value = require("animation.value")

local MotionValue = {}
MotionValue.__index = MotionValue

function MotionValue.new(initial)
    initial = Value.copy(initial)
    return setmetatable({
        current = initial,
        start = initial,
        target = initial,
        elapsed = 0,
        duration = 0,
        easing = Easing.linear,
        active = false,
    }, MotionValue)
end

function MotionValue:to(target, options)
    options = options or {}
    if Value.equal(target, self.target) then return self end
    local duration = math.max(0, options.duration or 0)
    if not options.preserve_speed and self.active
        and Value.equal(target, self.start)
    then
        local distance = Value.distance(self.start, self.target)
        if distance > 0 then
            duration = duration * Value.distance(self.current, target) / distance
        end
    end
    self.start = Value.copy(self.current)
    self.target = Value.copy(target)
    self.elapsed = 0
    self.duration = duration
    self.easing = Easing.resolve(options.ease)
    self.active = self.duration > 0 and self.start ~= self.target
    if not self.active then self.current = target end
    return self
end

function MotionValue:set(value)
    value = Value.copy(value)
    self.current, self.start, self.target = value, Value.copy(value), Value.copy(value)
    self.elapsed, self.duration, self.active = 0, 0, false
    return self
end

function MotionValue:get()
    return Value.copy(self.current)
end

function MotionValue:is_settled()
    return not self.active
end

function MotionValue:update(dt)
    if not self.active then return end
    self.elapsed = math.min(self.duration, self.elapsed + math.max(0, dt or 0))
    local progress = self.duration == 0 and 1 or self.elapsed / self.duration
    local eased = self.easing(progress)
    self.current = Value.interpolate(self.start, self.target, eased)
    if progress >= 1 then
        self.current = Value.copy(self.target)
        self.active = false
    end
end

return MotionValue
