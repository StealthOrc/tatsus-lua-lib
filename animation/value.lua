local Value = {}

function Value.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[Value.copy(key, seen)] = Value.copy(child, seen) end
    return result
end

function Value.equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not Value.equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

function Value.interpolate(from, to, progress)
    if type(from) == "number" and type(to) == "number" then
        return from + (to - from) * progress
    end
    assert(type(from) == "table" and type(to) == "table",
        "animated values must have matching numeric shapes")
    local result = {}
    for key, target in pairs(to) do
        assert(from[key] ~= nil, "animated values must have matching keys: " .. tostring(key))
        result[key] = Value.interpolate(from[key], target, progress)
    end
    for key in pairs(from) do
        assert(to[key] ~= nil, "animated values must have matching keys: " .. tostring(key))
    end
    return result
end

local function squared_distance(from, to)
    if type(from) == "number" and type(to) == "number" then
        local difference = to - from
        return difference * difference
    end
    assert(type(from) == "table" and type(to) == "table",
        "animated values must have matching numeric shapes")
    local total = 0
    for key, target in pairs(to) do
        assert(from[key] ~= nil, "animated values must have matching keys: " .. tostring(key))
        total = total + squared_distance(from[key], target)
    end
    return total
end

function Value.distance(from, to)
    return math.sqrt(squared_distance(from, to))
end

return Value
