local FontCache = {}
FontCache.__index = FontCache

function FontCache.new(styles)
    return setmetatable({styles = styles, cache = {}}, FontCache)
end

function FontCache:with_styles(styles)
    return setmetatable({styles = styles, cache = self.cache}, FontCache)
end

function FontCache:text_style(style)
    if type(style) == "table" then
        local result = self.styles:text_style("default")
        self.styles.merge(result, style)
        return result
    end
    return self.styles:text_style(style)
end

function FontCache:get(style, scale)
    style = self:text_style(style)
    local family = assert(self.styles.values.fonts[style.font or "default"], "unknown font family: " .. tostring(style.font))
    local path = family[style.weight or "regular"] or family.regular
    local size = math.max(1, math.floor((style.size or 16) * scale + 0.5))
    local filter = family.filter or "nearest"
    local key = table.concat({tostring(path or "<default>"), tostring(size), filter}, "\0")
    if not self.cache[key] then
        local font
        if path then
            local ok, result = pcall(love.graphics.newFont, path, size)
            if not ok then
                error("failed to load font '" .. tostring(path) .. "': " .. tostring(result), 2)
            end
            font = result
        else
            font = love.graphics.newFont(size)
        end
        font:setFilter(filter, filter)
        self.cache[key] = font
    end
    return self.cache[key], style
end

function FontCache:measure(text, style, scale)
    local font, resolved = self:get(style, scale)
    return font:getWidth(tostring(text or "")), font:getHeight(), font, resolved
end

return FontCache
