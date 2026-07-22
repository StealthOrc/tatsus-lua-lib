local Shader = {}

local Cache = {}
Cache.__index = Cache

local automatic_uniforms = {
    time = function(environment)
        return environment.context.time
    end,
    rect_origin = function(environment)
        local rect = environment.item.visual_rect or environment.item.rect
        return {rect.x, rect.y}
    end,
    rect_size = function(environment)
        local rect = environment.item.visual_rect or environment.item.rect
        return {rect.w, rect.h}
    end,
    viewport_size = function(environment)
        return {environment.layout.width, environment.layout.height}
    end,
    opacity = function(environment)
        return environment.alpha
    end,
}

local function has_uniform(shader, name)
    return shader.hasUniform == nil or shader:hasUniform(name)
end

local function send(shader, name, value)
    if value ~= nil and has_uniform(shader, name) then
        shader:send(name, value)
    end
end

local function normalize(spec)
    if type(spec) == "string" then return spec, {} end
    assert(type(spec) == "table", "shader surface expects a shader name or specification")
    return assert(spec.name or spec.shader, "shader specification requires 'name'"), spec.uniforms or {}
end

function Cache.new(registry)
    return setmetatable({registry = registry or {}, loaded = {}}, Cache)
end

function Cache:get(name)
    local configured = self.registry[name]
    assert(configured ~= nil, "unknown UI shader: " .. tostring(name))
    if self.loaded[name] then return self.loaded[name] end

    if type(configured) == "userdata" then
        self.loaded[name] = configured
        return configured
    end

    local source
    if type(configured) == "string" then
        local message
        source, message = love.filesystem.read(configured)
        assert(source, "failed to read UI shader '" .. tostring(name) .. "' from '"
            .. configured .. "': " .. tostring(message))
    elseif type(configured) == "table" then
        source = configured.source
        if not source and configured.path then
            local message
            source, message = love.filesystem.read(configured.path)
            assert(source, "failed to read UI shader '" .. tostring(name) .. "' from '"
                .. tostring(configured.path) .. "': " .. tostring(message))
        end
    end
    assert(type(source) == "string", "UI shader '" .. tostring(name) .. "' requires a path or source")

    local ok, compiled = pcall(love.graphics.newShader, source)
    assert(ok, "failed to compile UI shader '" .. tostring(name) .. "': " .. tostring(compiled))
    self.loaded[name] = compiled
    return compiled
end

function Cache:with(spec, environment, draw)
    if spec == nil or spec == false then return draw() end

    local name, uniforms = normalize(spec)
    local shader = self:get(name)
    for uniform, resolve in pairs(automatic_uniforms) do
        send(shader, uniform, resolve(environment))
    end
    for uniform, value in pairs(uniforms) do
        if type(value) == "function" then value = value(environment) end
        send(shader, uniform, value)
    end

    local previous = love.graphics.getShader()
    love.graphics.setShader(shader)
    local result = {pcall(draw)}
    love.graphics.setShader(previous)
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2)
end

Shader.Cache = Cache

return Shader
