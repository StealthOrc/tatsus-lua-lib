local Localization = {}
Localization.__index = Localization

local function normalizeLocale(locale, fallback)
    local normalized = tostring(locale or fallback or "en"):lower()
    if normalized == "" then
        return tostring(fallback or "en"):lower()
    end
    return normalized
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = deepCopy(nestedValue)
    end
    return copy
end

local function lookup(root, key)
    local current = root
    for part in tostring(key or ""):gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[part]
        if current == nil then
            return nil
        end
    end
    return current
end

local function interpolate(template, params)
    if type(template) ~= "string" then
        return template
    end

    return (template:gsub("{([%w_]+)}", function(name)
        if params and params[name] ~= nil then
            return tostring(params[name])
        end
        return "{" .. name .. "}"
    end))
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

local function resolveLocalePath(path, locale)
    if type(path) == "function" then
        return path(locale)
    end

    if type(path) ~= "string" or path == "" then
        return nil, "Localization path is required"
    end

    if path:find("{locale}", 1, true) then
        return (path:gsub("{locale}", locale))
    end

    return path
end

local function parseLocale(parser, content, context)
    if not parser then
        return nil, "Localization parser is required"
    end

    if type(parser) == "function" then
        return parser(content, context)
    end

    if type(parser.parse) == "function" then
        return parser.parse(content, context)
    end

    if type(parser.decode) == "function" then
        return parser.decode(content, context)
    end

    return nil, "Localization parser must be a function or expose parse(content) or decode(content)"
end

local function readError(locale, path, err)
    local message = "Missing locale file '" .. tostring(path) .. "' for locale '" .. tostring(locale) .. "'"
    if err then
        message = message .. ": " .. tostring(err)
    end
    return message
end

local function parseError(locale, path, err)
    local message = "Unable to parse locale file '" .. tostring(path) .. "' for locale '" .. tostring(locale) .. "'"
    if err then
        message = message .. ": " .. tostring(err)
    end
    return message
end

local function missingKeyError(key, currentLocale, fallbackLocale)
    if currentLocale ~= fallbackLocale then
        return "Missing localization key '" .. tostring(key) .. "' for locale '" .. tostring(currentLocale)
            .. "' and fallback locale '" .. tostring(fallbackLocale) .. "'"
    end

    return "Missing localization key '" .. tostring(key) .. "' for locale '" .. tostring(currentLocale) .. "'"
end

function Localization.new(config)
    config = config or {}

    local fallbackLocale = normalizeLocale(config.fallbackLocale, "en")
    local locale = normalizeLocale(config.locale, fallbackLocale)

    return setmetatable({
        currentLocale = locale,
        fallbackLocale = fallbackLocale,
        filesystem = config.filesystem,
        path = config.path,
        parser = config.parser,
        locales = {},
        loadErrors = {},
    }, Localization)
end

function Localization.normalizeLocale(locale, fallback)
    return normalizeLocale(locale, fallback)
end

function Localization:localePath(locale)
    return resolveLocalePath(self.path, normalizeLocale(locale, self.fallbackLocale))
end

function Localization:ensureLocale(locale)
    local targetLocale = normalizeLocale(locale, self.currentLocale or self.fallbackLocale)
    if self.locales[targetLocale] ~= nil then
        return self.locales[targetLocale]
    end

    local path, pathErr = self:localePath(targetLocale)
    if not path then
        self.loadErrors[targetLocale] = pathErr
        return nil, pathErr
    end

    local filesystem = defaultFilesystem(self.filesystem)
    if not filesystem or type(filesystem.read) ~= "function" then
        self.loadErrors[targetLocale] = "No filesystem reader is available for locale '" .. targetLocale .. "'"
        return nil, self.loadErrors[targetLocale]
    end

    local content, readErr = filesystem.read(path)
    if not content then
        self.loadErrors[targetLocale] = readError(targetLocale, path, readErr)
        return nil, self.loadErrors[targetLocale]
    end

    local parsed, parserErr = parseLocale(self.parser, content, {
        locale = targetLocale,
        path = path,
    })
    if not parsed then
        self.loadErrors[targetLocale] = parseError(targetLocale, path, parserErr)
        return nil, self.loadErrors[targetLocale]
    end

    if type(parsed) ~= "table" then
        self.loadErrors[targetLocale] = "Locale parser must return a table for '" .. tostring(path) .. "'"
        return nil, self.loadErrors[targetLocale]
    end

    self.loadErrors[targetLocale] = nil
    self.locales[targetLocale] = parsed
    return parsed
end

function Localization:load(locale)
    local targetLocale = normalizeLocale(locale, self.currentLocale or self.fallbackLocale)
    local parsed, err = self:ensureLocale(targetLocale)
    if parsed then
        self.currentLocale = targetLocale
        return true
    end

    if targetLocale ~= self.fallbackLocale then
        local fallback = self:ensureLocale(self.fallbackLocale)
        if fallback then
            self.currentLocale = self.fallbackLocale
            return true, err
        end
    end

    return nil, err
end

function Localization:setLocale(locale)
    return self:load(locale)
end

function Localization:getLocale()
    return self.currentLocale
end

function Localization:getLoadError(locale)
    return self.loadErrors[normalizeLocale(locale, self.currentLocale or self.fallbackLocale)]
end

function Localization:raw(key)
    local current, currentErr = self:ensureLocale(self.currentLocale)
    local fallback, fallbackErr = self:ensureLocale(self.fallbackLocale)

    local value = lookup(current, key)
    if value ~= nil then
        return value, currentErr
    end

    value = lookup(fallback, key)
    if value ~= nil then
        return value, currentErr
    end

    return nil, currentErr or fallbackErr or missingKeyError(key, self.currentLocale, self.fallbackLocale)
end

function Localization:has(key)
    local value, err = self:raw(key)
    return value ~= nil, err
end

function Localization:t(key, params, fallback)
    local value, err = self:raw(key)
    if value == nil then
        if fallback ~= nil then
            return interpolate(fallback, params), err
        end
        return "[[" .. tostring(key) .. "]]", err
    end

    if type(value) == "table" then
        return deepCopy(value), err
    end

    return interpolate(value, params), err
end

return Localization
