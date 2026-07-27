local Svg = {}
Svg.__index = Svg

local polygon_cache = setmetatable({}, {__mode = "k"})

local function tokenize(data)
    local tokens = {}
    local index = 1
    while index <= #data do
        local character = data:sub(index, index)
        if character:match("[%s,]") then
            index = index + 1
        elseif character:match("%a") then
            tokens[#tokens + 1] = character
            index = index + 1
        else
            local first = index
            if character == "+" or character == "-" then index = index + 1 end
            while data:sub(index, index):match("%d") do index = index + 1 end
            if data:sub(index, index) == "." then
                index = index + 1
                while data:sub(index, index):match("%d") do index = index + 1 end
            end
            if data:sub(index, index):match("[eE]") then
                index = index + 1
                if data:sub(index, index):match("[+-]") then index = index + 1 end
                while data:sub(index, index):match("%d") do index = index + 1 end
            end
            tokens[#tokens + 1] = data:sub(first, index - 1)
        end
    end
    return tokens
end

local function command(token)
    return token and token:match("^%a$") ~= nil
end

local function curve(target, steps, sample)
    for step = 1, steps do
        local x, y = sample(step / steps)
        target[#target + 1] = {x, y}
    end
end

local function parse_path(data)
    local tokens = tokenize(data or "")
    local paths, current = {}, {}
    local index, active = 1, nil
    local x, y, start_x, start_y = 0, 0, 0, 0
    local last_control_x, last_control_y

    local function number()
        local value = tonumber(tokens[index])
        index = index + 1
        return value or 0
    end
    local function finish()
        if #current > 0 then paths[#paths + 1], current = current, {} end
    end

    while index <= #tokens do
        if command(tokens[index]) then
            active = tokens[index]
            index = index + 1
        end
        if not active then break end
        local relative = active:lower() == active
        local op = active:upper()

        if op == "M" then
            local first = true
            while index <= #tokens and not command(tokens[index]) do
                local nx, ny = number(), number()
                if relative then nx, ny = x + nx, y + ny end
                if first then
                    finish()
                    current = {{nx, ny}}
                    start_x, start_y, first = nx, ny, false
                else
                    current[#current + 1] = {nx, ny}
                end
                x, y = nx, ny
            end
            active = relative and "l" or "L"
            last_control_x, last_control_y = nil, nil
        elseif op == "L" then
            while index <= #tokens and not command(tokens[index]) do
                local nx, ny = number(), number()
                if relative then nx, ny = x + nx, y + ny end
                current[#current + 1], x, y = {nx, ny}, nx, ny
            end
            last_control_x, last_control_y = nil, nil
        elseif op == "H" then
            while index <= #tokens and not command(tokens[index]) do
                local nx = number()
                x = relative and x + nx or nx
                current[#current + 1] = {x, y}
            end
            last_control_x, last_control_y = nil, nil
        elseif op == "V" then
            while index <= #tokens and not command(tokens[index]) do
                local ny = number()
                y = relative and y + ny or ny
                current[#current + 1] = {x, y}
            end
            last_control_x, last_control_y = nil, nil
        elseif op == "C" or op == "S" then
            while index <= #tokens and not command(tokens[index]) do
                local x1, y1
                if op == "C" then
                    x1, y1 = number(), number()
                    if relative then x1, y1 = x + x1, y + y1 end
                else
                    x1 = last_control_x and 2 * x - last_control_x or x
                    y1 = last_control_y and 2 * y - last_control_y or y
                end
                local x2, y2, x3, y3 = number(), number(), number(), number()
                if relative then x2, y2, x3, y3 = x + x2, y + y2, x + x3, y + y3 end
                local x0, y0 = x, y
                curve(current, 16, function(t)
                    local inverse = 1 - t
                    return inverse ^ 3 * x0 + 3 * inverse ^ 2 * t * x1 + 3 * inverse * t ^ 2 * x2 + t ^ 3 * x3,
                        inverse ^ 3 * y0 + 3 * inverse ^ 2 * t * y1 + 3 * inverse * t ^ 2 * y2 + t ^ 3 * y3
                end)
                x, y, last_control_x, last_control_y = x3, y3, x2, y2
            end
        elseif op == "Q" or op == "T" then
            while index <= #tokens and not command(tokens[index]) do
                local x1, y1
                if op == "Q" then
                    x1, y1 = number(), number()
                    if relative then x1, y1 = x + x1, y + y1 end
                else
                    x1 = last_control_x and 2 * x - last_control_x or x
                    y1 = last_control_y and 2 * y - last_control_y or y
                end
                local x2, y2 = number(), number()
                if relative then x2, y2 = x + x2, y + y2 end
                local x0, y0 = x, y
                curve(current, 14, function(t)
                    local inverse = 1 - t
                    return inverse ^ 2 * x0 + 2 * inverse * t * x1 + t ^ 2 * x2,
                        inverse ^ 2 * y0 + 2 * inverse * t * y1 + t ^ 2 * y2
                end)
                x, y, last_control_x, last_control_y = x2, y2, x1, y1
            end
        elseif op == "Z" then
            current[#current + 1] = {start_x, start_y}
            finish()
            x, y = start_x, start_y
            last_control_x, last_control_y = nil, nil
            active = nil
        else
            error("unsupported SVG path command: " .. tostring(active))
        end
    end
    finish()
    return paths
end

local function attributes(raw)
    local result = {}
    for key, quote, value in raw:gmatch("([%w_:%-]+)%s*=%s*(['\"])(.-)%2") do
        result[key] = value
    end
    return result
end

local function color(value)
    if not value or value == "none" or value == "currentColor" then return nil end
    local hex = value:match("^#(%x%x%x%x%x%x)$")
    if hex then
        return {tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1}
    end
    local short = value:match("^#(%x%x%x)$")
    if short then
        return {tonumber(short:sub(1, 1):rep(2), 16) / 255, tonumber(short:sub(2, 2):rep(2), 16) / 255, tonumber(short:sub(3, 3):rep(2), 16) / 255, 1}
    end
    local mode, body = value:match("^(rgba?)%((.-)%)$")
    if mode then
        local values = {}
        for part in body:gmatch("[^,%s]+") do values[#values + 1] = tonumber(part) or 0 end
        return {values[1] / 255, values[2] / 255, values[3] / 255, mode == "rgba" and (values[4] or 1) or 1}
    end
    return nil
end

local function viewbox(svg, root)
    local values = {}
    for value in tostring(root.viewBox or ""):gmatch("[-+]?[%d%.]+") do values[#values + 1] = tonumber(value) end
    if #values >= 4 then return {x = values[1], y = values[2], w = values[3], h = values[4]} end
    return {x = 0, y = 0, w = tonumber((root.width or ""):match("[%d%.]+")) or 24, h = tonumber((root.height or ""):match("[%d%.]+")) or 24}
end

function Svg.parse(svg)
    local root_raw = svg:match("<svg%s*(.-)>") or ""
    local root = attributes(root_raw)
    local icon = {viewbox = viewbox(svg, root), items = {}}
    for kind, raw in svg:gmatch("<([%a]+)%s+(.-)/?>") do
        if kind == "path" or kind == "line" or kind == "circle" then
            local attrs = attributes(raw)
            local fill_value = attrs.fill or root.fill or (attrs.stroke and "none" or "#000000")
            local stroke_value = attrs.stroke or root.stroke
            local item = {
                kind = kind,
                fill = fill_value ~= "none",
                fill_color = color(fill_value),
                fill_rule = attrs["fill-rule"] or root["fill-rule"],
                color_slot = attrs["data-color"],
                stroke = stroke_value ~= nil and stroke_value ~= "none",
                stroke_color = color(stroke_value),
                stroke_width = tonumber(attrs["stroke-width"] or root["stroke-width"]) or 1,
                opacity = tonumber(attrs.opacity or root.opacity) or 1,
            }
            if kind == "path" then
                item.paths = parse_path(attrs.d)
            elseif kind == "line" then
                item.x1, item.y1, item.x2, item.y2 = tonumber(attrs.x1) or 0, tonumber(attrs.y1) or 0, tonumber(attrs.x2) or 0, tonumber(attrs.y2) or 0
            else
                item.cx, item.cy, item.r = tonumber(attrs.cx) or 0, tonumber(attrs.cy) or 0, tonumber(attrs.r) or 0
            end
            icon.items[#icon.items + 1] = item
        end
    end
    return icon
end

function Svg.load(path)
    local raw, message = love.filesystem.read(path)
    if not raw then return nil, message or ("unable to read SVG: " .. tostring(path)) end
    local ok, icon = pcall(Svg.parse, raw)
    if not ok then return nil, icon end
    return icon
end

local function flatten(points)
    local result = {}
    for _, point in ipairs(points or {}) do
        result[#result + 1] = point[1]
        result[#result + 1] = point[2]
    end
    return result
end

local function normalized(points)
    local result = {}
    for _, point in ipairs(points or {}) do
        local previous = result[#result]
        if not previous
            or math.abs(previous[1] - point[1]) > 0.000001
            or math.abs(previous[2] - point[2]) > 0.000001 then
            result[#result + 1] = point
        end
    end
    if #result > 2 then
        local first = result[1]
        local last = result[#result]
        if math.abs(first[1] - last[1]) <= 0.000001
            and math.abs(first[2] - last[2]) <= 0.000001 then
            result[#result] = nil
        end
    end
    return result
end

local function polygon(points)
    local cached = polygon_cache[points]
    if cached == nil then
        local flat = flatten(normalized(points))
        if #flat < 6 then cached = false else
            local ok, triangles = pcall(love.math.triangulate, flat)
            cached = ok and triangles or false
        end
        polygon_cache[points] = cached
    end
    if cached then
        for _, triangle in ipairs(cached) do love.graphics.polygon("fill", triangle) end
    end
end

local set_color

local function signed_area(points)
    local area = 0
    for index = 1, #points do
        local current = points[index]
        local following = points[index % #points + 1]
        area = area + current[1] * following[2] - following[1] * current[2]
    end
    return area / 2
end

local function tint_for(tint, color_slot)
    if type(tint) ~= "table" or tint[1] ~= nil then return tint end
    return color_slot and tint[color_slot] or tint.default
end

local function filled_paths(item, box, selected, tint, alpha)
    tint = tint_for(tint, item.color_slot)
    if #item.paths <= 1 then
        set_color(selected, tint, alpha)
        if item.paths[1] then polygon(item.paths[1]) end
        return
    end

    for index, path in ipairs(item.paths) do
        local action
        if item.fill_rule == "evenodd" then
            action = "invert"
        else
            action = signed_area(path) < 0 and "decrementwrap" or "incrementwrap"
        end
        love.graphics.stencil(function() polygon(path) end, action, 1, index > 1)
    end
    love.graphics.setStencilTest("notequal", 0)
    set_color(selected, tint, alpha)
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h)
    love.graphics.setStencilTest()
end

set_color = function(selected, tint, alpha)
    selected = tint or selected or {1, 1, 1, 1}
    love.graphics.setColor(selected[1], selected[2], selected[3], (selected[4] or 1) * alpha)
end

function Svg.draw(icon, x, y, width, height, tint, alpha, fit)
    if not icon then return false end
    alpha = alpha or 1
    local box = icon.viewbox
    local scale_x = width / math.max(1, box.w)
    local scale_y = height / math.max(1, box.h)
    if fit ~= "stretch" then
        local scale = math.min(scale_x, scale_y)
        scale_x, scale_y = scale, scale
    end
    love.graphics.push("all")
    love.graphics.translate(x + width / 2, y + height / 2)
    love.graphics.scale(scale_x, scale_y)
    love.graphics.translate(-(box.x + box.w / 2), -(box.y + box.h / 2))
    for _, item in ipairs(icon.items) do
        local item_alpha = alpha * item.opacity
        if item.kind == "path" then
            if item.fill then
                filled_paths(item, box, item.fill_color, tint, item_alpha)
            end
            if item.stroke then
                set_color(
                    item.stroke_color,
                    tint_for(tint, item.color_slot),
                    item_alpha
                )
                love.graphics.setLineWidth(item.stroke_width)
                for _, path in ipairs(item.paths) do
                    local flat = flatten(path)
                    if #flat >= 4 then love.graphics.line(flat) end
                end
            end
        elseif item.kind == "line" then
            set_color(
                item.stroke_color,
                tint_for(tint, item.color_slot),
                item_alpha
            )
            love.graphics.setLineWidth(item.stroke_width)
            love.graphics.line(item.x1, item.y1, item.x2, item.y2)
        elseif item.kind == "circle" then
            local item_tint = tint_for(tint, item.color_slot)
            if item.fill then set_color(item.fill_color, item_tint, item_alpha); love.graphics.circle("fill", item.cx, item.cy, item.r) end
            if item.stroke then set_color(item.stroke_color, item_tint, item_alpha); love.graphics.setLineWidth(item.stroke_width); love.graphics.circle("line", item.cx, item.cy, item.r) end
        end
    end
    love.graphics.pop()
    return true
end

function Svg.drawBackdrop(icon, x, y, width, height, color, alpha)
    if not icon then return false end
    alpha = alpha or 1
    local box = icon.viewbox
    local scale = math.min(
        width / math.max(1, box.w),
        height / math.max(1, box.h)
    )
    love.graphics.push("all")
    love.graphics.translate(x + width / 2, y + height / 2)
    love.graphics.scale(scale)
    love.graphics.translate(
        -(box.x + box.w / 2),
        -(box.y + box.h / 2)
    )
    for _, item in ipairs(icon.items) do
        if item.fill then
            set_color(color, nil, alpha * item.opacity)
            if item.kind == "path" then
                if #item.paths <= 1 then
                    if item.paths[1] then polygon(item.paths[1]) end
                else
                    for _, path in ipairs(item.paths) do
                        if signed_area(path) >= 0 then polygon(path) end
                    end
                end
            elseif item.kind == "circle" then
                love.graphics.circle(
                    "fill",
                    item.cx,
                    item.cy,
                    item.r
                )
            end
        end
    end
    love.graphics.pop()
    return true
end

local Cache = {}
Cache.__index = Cache

function Cache.new(registry)
    return setmetatable({registry = registry or {}, loaded = {}}, Cache)
end

function Cache:get(name)
    local path = self.registry[name] or name
    assert(path, "unknown SVG icon: " .. tostring(name))
    if self.loaded[path] == nil then
        local icon, message = Svg.load(path)
        self.loaded[path] = icon or false
        if not icon then error("failed to load SVG '" .. tostring(path) .. "': " .. tostring(message)) end
    end
    return self.loaded[path]
end

function Cache:dimensions(name)
    local icon = self:get(name)
    return icon.viewbox.w, icon.viewbox.h
end

function Cache:draw(name, x, y, width, height, tint, alpha)
    return Svg.draw(self:get(name), x, y, width, height, tint, alpha)
end

function Cache:drawBackdrop(
    name,
    x,
    y,
    width,
    height,
    color,
    alpha
)
    return Svg.drawBackdrop(
        self:get(name),
        x,
        y,
        width,
        height,
        color,
        alpha
    )
end

Svg.Cache = Cache

return Svg
