local Toml = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseArray(raw)
    local body = trim(raw:sub(2, -2))
    local out = {}
    if body == "" then
        return out
    end

    for token in body:gmatch("[^,]+") do
        local value = trim(token)
        if value:match('^".*"$') then
            out[#out + 1] = value:sub(2, -2)
        elseif tonumber(value) then
            out[#out + 1] = tonumber(value)
        elseif value == "true" then
            out[#out + 1] = true
        elseif value == "false" then
            out[#out + 1] = false
        else
            out[#out + 1] = value
        end
    end

    return out
end

local function parseValue(raw)
    local value = trim(raw)
    if value:match('^".*"$') then
        return value:sub(2, -2)
    end

    if value:sub(1, 1) == "[" and value:sub(-1) == "]" then
        return parseArray(value)
    end

    if value == "true" then
        return true
    end

    if value == "false" then
        return false
    end

    local asNumber = tonumber(value)
    if asNumber ~= nil then
        return asNumber
    end

    return value
end

function Toml.parse(content)
    local result = {}

    for line in (content .. "\n"):gmatch("(.-)\n") do
        local cleaned = trim((line:gsub("#.*$", "")))
        if cleaned ~= "" then
            local key, rawValue = cleaned:match("^([%w_%.%-]+)%s*=%s*(.+)$")
            if key and rawValue then
                result[key] = parseValue(rawValue)
            end
        end
    end

    return result
end

function Toml.parseFile(path)
    local data = love.filesystem.read(path)
    if not data then
        return nil, "Unable to read TOML file: " .. path
    end

    return Toml.parse(data)
end

return Toml
