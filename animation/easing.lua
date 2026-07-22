local Easing = {}

function Easing.linear(value)
    return value
end

function Easing.in_quad(value)
    return value * value
end

function Easing.out_quad(value)
    return 1 - (1 - value) * (1 - value)
end

function Easing.in_out_quad(value)
    if value < 0.5 then return 2 * value * value end
    return 1 - ((-2 * value + 2) ^ 2) / 2
end

function Easing.in_cubic(value)
    return value * value * value
end

function Easing.out_cubic(value)
    return 1 - (1 - value) ^ 3
end

function Easing.in_out_cubic(value)
    if value < 0.5 then return 4 * value * value * value end
    return 1 - ((-2 * value + 2) ^ 3) / 2
end

function Easing.resolve(value)
    if type(value) == "function" then return value end
    local name = value or "linear"
    return assert(Easing[name], "unknown easing: " .. tostring(name))
end

return Easing
