local LayerStack = {}
LayerStack.__index = LayerStack

local default_layers = {
    base = 0,
    overlay = 100,
    popover = 200,
    tooltip = 300,
}

local function copy_layers(config)
    local result = {}
    for name, value in pairs(default_layers) do result[name] = value end
    for name, value in pairs(config or {}) do result[name] = value end
    return result
end

function LayerStack.new(layers)
    return setmetatable({entries = {}, by_key = {}, layers = copy_layers(layers), sequence = 0}, LayerStack)
end

function LayerStack:resolve_layer(value)
    value = value or "overlay"
    if type(value) == "number" then return value end
    return assert(self.layers[value], "unknown UI layer: " .. tostring(value))
end

function LayerStack:clear()
    self.entries, self.by_key = {}, {}
end

function LayerStack:push(view, options)
    options = options or {}
    local key = options.key or view.id
    assert(type(key) == "string" and key ~= "", "View Layer requires a non-empty key")
    assert(not self.by_key[key], "duplicate View Layer key: " .. key)
    self.sequence = self.sequence + 1
    local entry = {
        key = key,
        view = view,
        model = options.model or {},
        layer = self:resolve_layer(options.layer),
        pointer = options.pointer or "block",
        keyboard = options.keyboard or "block",
        transition = options.transition,
        order = self.sequence,
        layout = nil,
    }
    self.by_key[key] = entry
    self.entries[#self.entries + 1] = entry
    table.sort(self.entries, function(left, right)
        return left.layer == right.layer and left.order < right.order or left.layer < right.layer
    end)
    return entry
end

function LayerStack:get(key)
    return self.by_key[key]
end

function LayerStack:remove(key)
    local entry = self.by_key[key]
    if not entry then return nil end
    self.by_key[key] = nil
    for index, candidate in ipairs(self.entries) do
        if candidate == entry then
            table.remove(self.entries, index)
            break
        end
    end
    return entry
end

function LayerStack:pop()
    local entry = self.entries[#self.entries]
    return entry and self:remove(entry.key) or nil
end

return LayerStack
