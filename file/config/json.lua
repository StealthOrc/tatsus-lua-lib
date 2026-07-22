local Json = {}

Json.null = {}

local utf8Lib = nil
do
    local ok, module = pcall(require, "utf8")
    if ok then
        utf8Lib = module
    end
end

local function codepointToUtf8(codepoint)
    if utf8Lib and type(utf8Lib.char) == "function" then
        local ok, value = pcall(utf8Lib.char, codepoint)
        if ok then
            return value
        end
    end

    if codepoint <= 0x7f then
        return string.char(codepoint)
    elseif codepoint <= 0x7ff then
        return string.char(
            0xc0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0xffff then
        return string.char(
            0xe0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    elseif codepoint <= 0x10ffff then
        return string.char(
            0xf0 + math.floor(codepoint / 0x40000),
            0x80 + (math.floor(codepoint / 0x1000) % 0x40),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return nil
end

local function defaultFilesystem(filesystem)
    if filesystem then
        return filesystem
    end

    if love and love.filesystem then
        return love.filesystem
    end

    return nil
end

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
            return false
        end
        count = count + 1
    end

    return count == #value
end

local function encodeString(value)
    return "\"" .. value
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
        :gsub("[%z\001-\031]", function(character)
            return string.format("\\u%04x", string.byte(character))
        end) .. "\""
end

local function sortedKeys(value)
    local keys = {}
    for key, _ in pairs(value) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    return keys
end

local function encodeValue(value, seen)
    local kind = type(value)

    if value == Json.null or kind == "nil" then
        return "null"
    end

    if kind == "boolean" then
        return value and "true" or "false"
    end

    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("Cannot encode non-finite JSON number")
        end
        return tostring(value)
    end

    if kind == "string" then
        return encodeString(value)
    end

    if kind ~= "table" then
        error("Unsupported JSON value: " .. kind)
    end

    if seen[value] then
        error("Cannot encode cyclic JSON table")
    end
    seen[value] = true

    if isArray(value) then
        local items = {}
        for index = 1, #value do
            items[index] = encodeValue(value[index], seen)
        end
        seen[value] = nil
        return "[" .. table.concat(items, ",") .. "]"
    end

    local items = {}
    for _, key in ipairs(sortedKeys(value)) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" and keyKind ~= "boolean" then
            error("Unsupported JSON object key: " .. keyKind)
        end
        items[#items + 1] = encodeString(tostring(key)) .. ":" .. encodeValue(value[key], seen)
    end

    seen[value] = nil
    return "{" .. table.concat(items, ",") .. "}"
end

function Json.encode(value)
    return encodeValue(value, {})
end

Json.stringify = Json.encode

local function decodeError(position, message)
    return nil, string.format("JSON parse error at byte %d: %s", position, message)
end

local function skipWhitespace(text, index)
    while true do
        local character = text:sub(index, index)
        if character == "" or not character:match("%s") then
            return index
        end
        index = index + 1
    end
end

local parseValue

local function parseString(text, index)
    index = index + 1
    local fragments = {}

    while index <= #text do
        local character = text:sub(index, index)
        if character == "\"" then
            return table.concat(fragments), index + 1
        end

        if character == "\\" then
            local escaped = text:sub(index + 1, index + 1)
            if escaped == "\"" or escaped == "\\" or escaped == "/" then
                fragments[#fragments + 1] = escaped
                index = index + 2
            elseif escaped == "b" then
                fragments[#fragments + 1] = "\b"
                index = index + 2
            elseif escaped == "f" then
                fragments[#fragments + 1] = "\f"
                index = index + 2
            elseif escaped == "n" then
                fragments[#fragments + 1] = "\n"
                index = index + 2
            elseif escaped == "r" then
                fragments[#fragments + 1] = "\r"
                index = index + 2
            elseif escaped == "t" then
                fragments[#fragments + 1] = "\t"
                index = index + 2
            elseif escaped == "u" then
                local hex = text:sub(index + 2, index + 5)
                if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
                    return decodeError(index, "invalid unicode escape")
                end

                local characterValue = codepointToUtf8(tonumber(hex, 16))
                if not characterValue then
                    return decodeError(index, "unsupported unicode escape")
                end

                fragments[#fragments + 1] = characterValue
                index = index + 6
            else
                return decodeError(index, "invalid escape sequence")
            end
        elseif character:byte() < 32 then
            return decodeError(index, "unescaped control character in string")
        else
            fragments[#fragments + 1] = character
            index = index + 1
        end
    end

    return decodeError(index, "unterminated string")
end

local function parseNumber(text, index)
    local startIndex = index

    if text:sub(index, index) == "-" then
        index = index + 1
    end

    local firstDigit = text:sub(index, index)
    if firstDigit == "0" then
        index = index + 1
    elseif firstDigit:match("%d") then
        repeat
            index = index + 1
        until not text:sub(index, index):match("%d")
    else
        return decodeError(startIndex, "invalid number")
    end

    if text:sub(index, index) == "." then
        index = index + 1
        if not text:sub(index, index):match("%d") then
            return decodeError(startIndex, "invalid number")
        end
        repeat
            index = index + 1
        until not text:sub(index, index):match("%d")
    end

    local exponent = text:sub(index, index)
    if exponent == "e" or exponent == "E" then
        index = index + 1
        local sign = text:sub(index, index)
        if sign == "+" or sign == "-" then
            index = index + 1
        end
        if not text:sub(index, index):match("%d") then
            return decodeError(startIndex, "invalid number")
        end
        repeat
            index = index + 1
        until not text:sub(index, index):match("%d")
    end

    local raw = text:sub(startIndex, index - 1)
    local number = tonumber(raw)
    if number == nil then
        return decodeError(startIndex, "invalid number")
    end

    return number, index
end

local function parseLiteral(text, index, literal, value)
    if text:sub(index, index + #literal - 1) ~= literal then
        return decodeError(index, "expected " .. literal)
    end
    return value, index + #literal
end

local function parseArray(text, index, nullValue)
    index = skipWhitespace(text, index + 1)
    local items = {}

    if text:sub(index, index) == "]" then
        return items, index + 1
    end

    while true do
        local value
        value, index = parseValue(text, index, nullValue)
        if index == nil then
            return nil, value
        end
        items[#items + 1] = value

        index = skipWhitespace(text, index)
        local character = text:sub(index, index)
        if character == "]" then
            return items, index + 1
        end
        if character ~= "," then
            return decodeError(index, "expected ',' or ']'")
        end
        index = skipWhitespace(text, index + 1)
    end
end

local function parseObject(text, index, nullValue)
    index = skipWhitespace(text, index + 1)
    local object = {}

    if text:sub(index, index) == "}" then
        return object, index + 1
    end

    while true do
        if text:sub(index, index) ~= "\"" then
            return decodeError(index, "expected string object key")
        end

        local key
        key, index = parseString(text, index)
        if index == nil then
            return nil, key
        end

        index = skipWhitespace(text, index)
        if text:sub(index, index) ~= ":" then
            return decodeError(index, "expected ':' after object key")
        end

        local value
        value, index = parseValue(text, skipWhitespace(text, index + 1), nullValue)
        if index == nil then
            return nil, value
        end
        object[key] = value

        index = skipWhitespace(text, index)
        local character = text:sub(index, index)
        if character == "}" then
            return object, index + 1
        end
        if character ~= "," then
            return decodeError(index, "expected ',' or '}'")
        end
        index = skipWhitespace(text, index + 1)
    end
end

parseValue = function(text, index, nullValue)
    index = skipWhitespace(text, index)
    local character = text:sub(index, index)

    if character == "" then
        return decodeError(index, "unexpected end of input")
    end

    if character == "\"" then
        return parseString(text, index)
    end
    if character == "{" then
        return parseObject(text, index, nullValue)
    end
    if character == "[" then
        return parseArray(text, index, nullValue)
    end
    if character == "t" then
        return parseLiteral(text, index, "true", true)
    end
    if character == "f" then
        return parseLiteral(text, index, "false", false)
    end
    if character == "n" then
        return parseLiteral(text, index, "null", nullValue)
    end
    if character == "-" or character:match("%d") then
        return parseNumber(text, index)
    end

    return decodeError(index, "unexpected character '" .. character .. "'")
end

function Json.decode(text, options)
    if type(text) ~= "string" then
        return nil, "JSON payload must be a string"
    end

    local nullValue = options and options.null or Json.null
    local value, index = parseValue(text, 1, nullValue)
    if index == nil then
        return nil, value
    end

    index = skipWhitespace(text, index)
    if index <= #text then
        return decodeError(index, "trailing data")
    end

    return value
end

Json.parse = Json.decode

function Json.parseFile(path, options)
    local filesystem = defaultFilesystem(options and options.filesystem)
    if not filesystem or type(filesystem.read) ~= "function" then
        return nil, "No filesystem reader is available for JSON file: " .. tostring(path)
    end

    local data, readErr = filesystem.read(path)
    if not data then
        return nil, readErr or ("Unable to read JSON file: " .. tostring(path))
    end

    return Json.decode(data, options)
end

function Json.writeFile(path, value, options)
    local filesystem = defaultFilesystem(options and options.filesystem)
    if not filesystem or type(filesystem.write) ~= "function" then
        return nil, "No filesystem writer is available for JSON file: " .. tostring(path)
    end

    local ok, err = filesystem.write(path, Json.encode(value))
    if not ok then
        return nil, err
    end

    return true
end

return Json
