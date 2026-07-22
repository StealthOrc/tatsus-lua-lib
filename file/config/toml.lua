local Toml = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local ESCAPE_MAP = {
    ['"'] = '"',
    ["\\"] = "\\",
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
}

local function stripComment(line)
    local inString = false
    local escaped = false

    for index = 1, #line do
        local character = line:sub(index, index)
        if inString then
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == '"' then
                inString = false
            end
        else
            if character == '"' then
                inString = true
            elseif character == "#" then
                return line:sub(1, index - 1)
            end
        end
    end

    return line
end

local function decodeString(raw)
    if raw:sub(1, 1) ~= '"' or raw:sub(-1) ~= '"' then
        return nil, "Expected a quoted TOML string"
    end

    local out = {}
    local escaped = false

    for index = 2, #raw - 1 do
        local character = raw:sub(index, index)
        if escaped then
            local decoded = ESCAPE_MAP[character]
            if not decoded then
                return nil, "Unsupported TOML escape \\" .. character
            end
            out[#out + 1] = decoded
            escaped = false
        elseif character == "\\" then
            escaped = true
        else
            out[#out + 1] = character
        end
    end

    if escaped then
        return nil, "Unterminated TOML escape sequence"
    end

    return table.concat(out)
end

local function splitArrayValues(body)
    local values = {}
    local buffer = {}
    local inString = false
    local escaped = false
    local depth = 0

    for index = 1, #body do
        local character = body:sub(index, index)
        if inString then
            buffer[#buffer + 1] = character
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == '"' then
                inString = false
            end
        else
            if character == '"' then
                inString = true
                buffer[#buffer + 1] = character
            elseif character == "[" then
                depth = depth + 1
                buffer[#buffer + 1] = character
            elseif character == "]" then
                depth = math.max(0, depth - 1)
                buffer[#buffer + 1] = character
            elseif character == "," and depth == 0 then
                values[#values + 1] = trim(table.concat(buffer))
                buffer = {}
            else
                buffer[#buffer + 1] = character
            end
        end
    end

    if inString then
        return nil, "Unterminated string in TOML array"
    end

    local trailing = trim(table.concat(buffer))
    if trailing ~= "" then
        values[#values + 1] = trailing
    end

    return values
end

local function parseArray(raw)
    local body = trim(raw:sub(2, -2))
    local out = {}
    if body == "" then
        return out
    end

    local values, valuesErr = splitArrayValues(body)
    if not values then
        return nil, valuesErr
    end

    for _, token in ipairs(values) do
        local value, valueErr = Toml.parseValue(token)
        if valueErr then
            return nil, valueErr
        end
        out[#out + 1] = value
    end

    return out
end

function Toml.parseValue(raw)
    local value = trim(raw)
    if value:match('^".*"$') then
        return decodeString(value)
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

local function ensureTable(root, path)
    local current = root

    for part in path:gmatch("[^%.]+") do
        if type(current[part]) ~= "table" then
            current[part] = {}
        end
        current = current[part]
    end

    return current
end

local function setValue(root, path, value)
    local current = root
    local parentPath, leaf = path:match("^(.*)%.([^.]+)$")

    if parentPath then
        current = ensureTable(root, parentPath)
    end

    current[leaf or path] = value
end

function Toml.parse(content)
    local result = {}
    local currentTable = result

    local lineNumber = 0
    for line in (content .. "\n"):gmatch("(.-)\n") do
        lineNumber = lineNumber + 1
        local cleaned = trim(stripComment(line))
        if cleaned ~= "" then
            local tablePath = cleaned:match("^%[([%w_%.%-]+)%]$")
            if tablePath then
                currentTable = ensureTable(result, tablePath)
            else
                local key, rawValue = cleaned:match("^([%w_%.%-]+)%s*=%s*(.+)$")
                if key and rawValue then
                    local parsedValue, parseErr = Toml.parseValue(rawValue)
                    if parseErr then
                        return nil, string.format("TOML parse error on line %d: %s", lineNumber, parseErr)
                    end
                    setValue(currentTable, key, parsedValue)
                else
                    return nil, string.format("TOML parse error on line %d: %s", lineNumber, cleaned)
                end
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
