local Units = {}

local unit_mt = {
    __tostring = function(value)
        return string.format("ui2d.%s(%s)", value.kind, tostring(value.value))
    end,
}

local function unit(kind, value)
    assert(type(value) == "number", kind .. " requires a number")
    return setmetatable({
        __ui2d_unit = true,
        kind = kind,
        value = value,
    }, unit_mt)
end

function Units.percent(value)
    return unit("percent", value)
end

function Units.em(value)
    return unit("em", value)
end

function Units.rem(value)
    return unit("rem", value)
end

function Units.is(value, kind)
    return type(value) == "table"
        and value.__ui2d_unit == true
        and (kind == nil or value.kind == kind)
end

function Units.resolve(value, available, context)
    context = context or {}
    if type(value) == "number" then
        return value * (context.scale or 1)
    end
    if not Units.is(value) then
        return value
    end
    if value.kind == "percent" then
        return (available or 0) * value.value
    elseif value.kind == "em" then
        return (context.font_size or context.root_font_size or 16) * value.value
    elseif value.kind == "rem" then
        return (context.root_font_size or 16) * value.value
    end
    error("unknown ui2d unit: " .. tostring(value.kind))
end

return Units
