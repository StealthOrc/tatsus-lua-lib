local Svg = require("graphics.svg")

local MediaCache = {}
MediaCache.__index = MediaCache

local function copy_registry(images, icons)
    local result = {}
    for name, value in pairs(icons or {}) do result[name] = value end
    for name, value in pairs(images or {}) do result[name] = value end
    return result
end

local function normalized_spec(value)
    if type(value) == "string" then return {path = value} end
    assert(type(value) == "table", "UI media entries must be paths or tables")
    return value
end

local function is_svg(path, spec)
    return spec.kind == "svg"
        or tostring(path):lower():match("%.svg$") ~= nil
end

local function frame_rect(asset, request)
    local spec = asset.spec
    local source_width, source_height =
        asset.image:getWidth(), asset.image:getHeight()
    local quad = request and request.quad or spec.quad
    if quad then
        return quad.x or quad[1] or 0,
            quad.y or quad[2] or 0,
            assert(quad.w or quad[3], "media quad requires width"),
            assert(quad.h or quad[4], "media quad requires height")
    end
    local frame_width = request and request.frame_width or spec.frame_width
    local frame_height = request and request.frame_height or spec.frame_height
    if not frame_width or not frame_height then
        return 0, 0, source_width, source_height
    end
    local columns = math.max(1, math.floor(source_width / frame_width))
    local frame = math.max(1, math.floor(
        request and request.frame or spec.frame or 1
    )) - 1
    return (frame % columns) * frame_width,
        math.floor(frame / columns) * frame_height,
        frame_width,
        frame_height
end

function MediaCache.new(images, icons)
    return setmetatable({
        registry = copy_registry(images, icons),
        loaded = {},
    }, MediaCache)
end

function MediaCache:get(name)
    local value = self.registry[name] or name
    assert(value, "unknown UI image: " .. tostring(name))
    local spec = normalized_spec(value)
    local path = spec.path
    assert(path or spec.image,
        "UI media entry requires a path or drawable image")
    local cache_key = value
    if self.loaded[cache_key] == nil then
        if spec.image then
            local filter = spec.filter or "linear"
            if spec.image.setFilter then
                spec.image:setFilter(filter, filter)
            end
            self.loaded[cache_key] = {
                kind = "raster",
                image = spec.image,
                spec = spec,
                quads = {},
            }
        elseif is_svg(path, spec) then
            local icon, message = Svg.load(path)
            if not icon then
                error("failed to load SVG '" .. tostring(path) .. "': "
                    .. tostring(message))
            end
            self.loaded[cache_key] = {
                kind = "svg",
                source = icon,
                spec = spec,
            }
        else
            local image = love.graphics.newImage(path)
            local filter = spec.filter or "linear"
            image:setFilter(filter, filter)
            self.loaded[cache_key] = {
                kind = "raster",
                image = image,
                spec = spec,
                quads = {},
            }
        end
    end
    return self.loaded[cache_key]
end

function MediaCache:dimensions(name, request)
    local asset = self:get(name)
    if asset.kind == "svg" then
        return asset.source.viewbox.w, asset.source.viewbox.h
    end
    local _, _, width, height = frame_rect(asset, request)
    return width, height
end

local function fitted_rect(x, y, width, height, source_width, source_height, fit)
    fit = fit or "contain"
    if fit == "stretch" then
        return x, y, width, height
    end
    if fit == "none" then
        return x, y, source_width, source_height
    end
    local scale_x = width / math.max(1, source_width)
    local scale_y = height / math.max(1, source_height)
    local scale = fit == "cover"
        and math.max(scale_x, scale_y)
        or math.min(scale_x, scale_y)
    local draw_width = source_width * scale
    local draw_height = source_height * scale
    return x + (width - draw_width) * 0.5,
        y + (height - draw_height) * 0.5,
        draw_width,
        draw_height
end

local function cover_scissor(x, y, width, height)
    local previous = {love.graphics.getScissor()}
    local clip_x, clip_y, clip_w, clip_h = x, y, width, height
    if previous[1] then
        local right = math.min(
            x + width,
            previous[1] + previous[3]
        )
        local bottom = math.min(
            y + height,
            previous[2] + previous[4]
        )
        clip_x = math.max(x, previous[1])
        clip_y = math.max(y, previous[2])
        clip_w = math.max(0, right - clip_x)
        clip_h = math.max(0, bottom - clip_y)
    end
    love.graphics.setScissor(clip_x, clip_y, clip_w, clip_h)
    return previous
end

local function restore_scissor(previous)
    if not previous then return end
    if previous[1] then
        love.graphics.setScissor(
            previous[1],
            previous[2],
            previous[3],
            previous[4]
        )
    else
        love.graphics.setScissor()
    end
end

function MediaCache:draw(name, x, y, width, height, tint, alpha, request)
    local asset = self:get(name)
    request = request or {}
    local source_width, source_height = self:dimensions(name, request)
    local draw_x, draw_y, draw_width, draw_height = fitted_rect(
        x, y, width, height, source_width, source_height, request.fit
    )
    local previous_scissor = request.fit == "cover"
        and cover_scissor(x, y, width, height)
        or nil
    if asset.kind == "svg" then
        local drawn = Svg.draw(
            asset.source,
            draw_x,
            draw_y,
            draw_width,
            draw_height,
            tint,
            alpha,
            request.fit
        )
        restore_scissor(previous_scissor)
        return drawn
    end

    local quad_x, quad_y, quad_width, quad_height = frame_rect(asset, request)
    local quad_key = table.concat({
        quad_x,
        quad_y,
        quad_width,
        quad_height,
    }, ":")
    local quad = asset.quads[quad_key]
    if not quad then
        quad = love.graphics.newQuad(
            quad_x,
            quad_y,
            quad_width,
            quad_height,
            asset.image:getDimensions()
        )
        asset.quads[quad_key] = quad
    end
    local color = tint or {1, 1, 1, 1}
    love.graphics.setColor(
        color[1] or 1,
        color[2] or 1,
        color[3] or 1,
        (color[4] or 1) * (alpha or 1)
    )
    love.graphics.draw(
        asset.image,
        quad,
        draw_x,
        draw_y,
        0,
        draw_width / math.max(1, quad_width),
        draw_height / math.max(1, quad_height)
    )
    restore_scissor(previous_scissor)
    return true
end

return MediaCache
