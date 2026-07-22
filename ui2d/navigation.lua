local Navigation = {}

local directions = {
    up = {axis = "vertical", step = -1, dx = 0, dy = -1},
    down = {axis = "vertical", step = 1, dx = 0, dy = 1},
    left = {axis = "horizontal", step = -1, dx = -1, dy = 0},
    right = {axis = "horizontal", step = 1, dx = 1, dy = 0},
}

local function visit(item, parent, navigation_enabled, result)
    item.parent = parent
    navigation_enabled = navigation_enabled and item.node.navigation ~= false
        and item.node.selectable ~= false
    item.navigation_enabled = navigation_enabled
    if item.interactive and navigation_enabled then
        result[#result + 1] = item
    end
    for _, child in ipairs(item.children or {}) do
        visit(child, item, navigation_enabled, result)
    end
end

function Navigation.build(layout)
    local result = {}
    visit(layout.root, nil, true, result)
    layout.navigable = result
    return result
end

local function enabled_descendants(item, result)
    result = result or {}
    if item.interactive and item.navigation_enabled and item.enabled then
        result[#result + 1] = item
    end
    for _, child in ipairs(item.children or {}) do enabled_descendants(child, result) end
    return result
end

function Navigation.first(layout, preferred)
    if preferred then
        local item = layout.by_id[preferred]
        if item and item.navigation_enabled and item.enabled then return item end
    end
    for _, item in ipairs(layout.navigable or {}) do
        if item.enabled then return item end
    end
    return nil
end

local function branch_below(item, ancestor)
    local branch = item
    while branch and branch.parent ~= ancestor do branch = branch.parent end
    return branch
end

local function group_axis(item)
    local config = type(item.node.navigation) == "table" and item.node.navigation or nil
    if config and config.axis then return config.axis end
    if item.kind == "row" then return "horizontal" end
    if item.kind == "column" then return "vertical" end
    return nil
end

local function group_wrap(item, fallback)
    local config = type(item.node.navigation) == "table" and item.node.navigation or nil
    if config and config.wrap ~= nil then return config.wrap end
    return fallback == true
end

local function ordinal_in(item, selected)
    local descendants = enabled_descendants(item)
    for index, candidate in ipairs(descendants) do
        if candidate == selected then return index end
    end
    return 1
end

local function entry_for(layout, target, source, selected, direction)
    local candidates = enabled_descendants(target)
    if #candidates == 0 then return nil end

    local compatible = source and group_axis(source) and group_axis(source) == group_axis(target)
        and group_axis(target) ~= direction.axis
    if compatible then
        return candidates[math.min(#candidates, ordinal_in(source, selected))]
    end

    local config = type(target.node.navigation) == "table" and target.node.navigation or nil
    local entry = config and config.entry
    if type(entry) == "string" then
        for _, candidate in ipairs(candidates) do
            if candidate.node.id == entry then return candidate end
        end
    elseif type(entry) == "function" then
        local id = entry({direction = direction, source = selected.node.id, target = target.node.id})
        if id and layout.by_id[id] then return layout.by_id[id] end
    end
    return candidates[1]
end

local function structural(layout, selected, direction, wrap)
    local ancestor = selected.parent
    while ancestor do
        if group_axis(ancestor) == direction.axis then
            local source = branch_below(selected, ancestor)
            local source_index
            for index, child in ipairs(ancestor.children or {}) do
                if child == source then source_index = index break end
            end
            if source_index then
                local count = #ancestor.children
                for offset = 1, count - 1 do
                    local index = source_index + direction.step * offset
                    if group_wrap(ancestor, wrap) then
                        index = ((index - 1) % count) + 1
                    elseif index < 1 or index > count then
                        break
                    end
                    local target = entry_for(layout, ancestor.children[index], source, selected, direction)
                    if target then return target end
                end
            end
        end
        ancestor = ancestor.parent
    end
    return nil
end

local function center(item)
    local rect = item.rect
    return rect.x + rect.w / 2, rect.y + rect.h / 2
end

local function orthogonal_group(item, direction)
    local ancestor = item.parent
    while ancestor do
        local axis = group_axis(ancestor)
        if axis and axis ~= direction.axis then return ancestor end
        ancestor = ancestor.parent
    end
    return nil
end

local function descends_from(item, ancestor)
    local current = item.parent
    while current do
        if current == ancestor then return true end
        current = current.parent
    end
    return false
end

local function spatial(layout, selected, direction)
    local sx, sy = center(selected)
    local excluded_group = orthogonal_group(selected, direction)
    local best, best_score
    for _, candidate in ipairs(layout.navigable or {}) do
        if candidate ~= selected and candidate.enabled
            and (not excluded_group or not descends_from(candidate, excluded_group))
        then
            local x, y = center(candidate)
            local dx, dy = x - sx, y - sy
            local primary = dx * direction.dx + dy * direction.dy
            if primary > 0.5 then
                local secondary = math.abs(dx * direction.dy - dy * direction.dx)
                local score = primary + secondary * 2.5
                if not best_score or score < best_score then
                    best, best_score = candidate, score
                end
            end
        end
    end
    return best
end

local function explicit_target(layout, selected, name, request)
    local edges = selected.node.navigate
    if type(edges) ~= "table" or edges[name] == nil then return nil, false end
    local target = edges[name]
    if type(target) == "function" then target = target(request) end
    if target == false then return nil, true end
    if type(target) == "table" then target = target.id end
    local item = type(target) == "string" and layout.by_id[target] or nil
    return item and item.navigation_enabled and item.enabled and item or nil, true
end

function Navigation.move(layout, selected_id, name, options, request)
    local direction = directions[name]
    if not direction then return nil end
    local selected = selected_id and layout.by_id[selected_id] or Navigation.first(layout)
    if not selected or not selected.enabled or not selected.navigation_enabled then
        return Navigation.first(layout, options and options.initial)
    end

    request = request or {}
    request.direction = name
    request.dx, request.dy = direction.dx, direction.dy
    request.current = selected.node.id

    local explicit, handled = explicit_target(layout, selected, name, request)
    if handled then return explicit end

    options = options or {}
    if type(options.resolve) == "function" then
        local resolved = options.resolve(request)
        if resolved ~= nil then
            if resolved == false then return nil end
            local id = type(resolved) == "table" and resolved.id or resolved
            local item = layout.by_id[id]
            return item and item.navigation_enabled and item.enabled and item or nil
        end
    end
    if options.mode == "manual" then return nil end

    return structural(layout, selected, direction, options.wrap)
        or spatial(layout, selected, direction)
end

function Navigation.direction(x, y, threshold)
    threshold = threshold or 0.5
    if math.max(math.abs(x or 0), math.abs(y or 0)) < threshold then return nil end
    if math.abs(x or 0) > math.abs(y or 0) then return x < 0 and "left" or "right" end
    return y < 0 and "up" or "down"
end

return Navigation
