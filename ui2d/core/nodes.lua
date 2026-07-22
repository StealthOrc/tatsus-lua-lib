local Nodes = {}

local kinds = {
    screen = true,
    row = true,
    column = true,
    stack = true,
    panel = true,
    text = true,
    icon = true,
    spacer = true,
}

local function construct(kind, spec)
    assert(kinds[kind], "unknown ui2d node kind: " .. tostring(kind))
    if kind == "text" and type(spec) == "string" then
        spec = {value = spec}
    elseif kind == "icon" and type(spec) == "string" then
        spec = {name = spec}
    else
        spec = spec or {}
    end
    assert(type(spec) == "table", kind .. " expects a table")

    local node = {kind = kind, children = {}}
    for key, value in pairs(spec) do
        if type(key) == "number" then
            node.children[#node.children + 1] = value
        elseif key ~= "children" then
            node[key] = value
        end
    end
    if spec.children then
        for _, child in ipairs(spec.children) do
            node.children[#node.children + 1] = child
        end
    end
    return node
end

function Nodes.register(kind)
    assert(type(kind) == "string" and kind ~= "", "node kind must be a non-empty string")
    assert(not kinds[kind], "duplicate ui2d node kind: " .. kind)
    kinds[kind] = true
end

Nodes.construct = construct

for kind in pairs(kinds) do
    Nodes[kind] = function(spec)
        return construct(kind, spec)
    end
end

function Nodes.view(id, definition)
    assert(type(id) == "string" and id ~= "", "view requires a non-empty id")
    local builder = definition
    local styles
    if type(definition) == "table" then
        builder = definition.build
        styles = definition.styles
    end
    assert(type(builder) == "function", "view requires a builder function")
    return {
        __ui2d_view = true,
        id = id,
        build = builder,
        styles = styles,
    }
end

return Nodes
