local Transform = require("ui2d.core.transform")
local Navigation = require("ui2d.core.navigation")
local LayoutValues = require("ui2d.core.layout_values")
local Button = require("ui2d.components.button")
local TextField = require("ui2d.components.text_field")

local Layout = {}

local resolve_token = LayoutValues.resolve_token
local length = LayoutValues.length
local dimension = LayoutValues.dimension
local insets = LayoutValues.insets

local measure

local function scoped_environment(node, env)
    if not node.styles then return env end
    local styles = env.styles:with(node.styles)
    local scoped = {}
    for key, value in pairs(env) do scoped[key] = value end
    scoped.styles = styles
    scoped.fonts = env.fonts:with_styles(styles)
    return scoped
end

local function measure_text(node, env)
    local text = tostring(node.value or "")
    local width, height, font, style = env.fonts:measure(text, node.style or node.text_style, env.scale)
    return {
        kind = "text",
        node = node,
        text = text,
        font = font,
        text_style = style,
        w = width,
        h = height,
    }
end

local function measure_icon(node, available_w, available_h, env)
    local source_w, source_h = env.icons:dimensions(assert(node.name, "icon requires a name"))
    local size = length(node.size or 24, math.min(available_w, available_h), env) or 0
    local width = node.width and dimension(node.width, available_w, size, env) or size * source_w / math.max(1, source_h)
    local height = node.height and dimension(node.height, available_h, size, env) or size
    return {kind = "icon", node = node, w = width, h = height}
end

local function measure_spacer(node, available_w, available_h, env)
    return {
        kind = "spacer",
        node = node,
        w = dimension(node.width, available_w, 0, env),
        h = dimension(node.height, available_h, 0, env),
    }
end

local function measure_container(node, available_w, available_h, env)
    local padding = insets(node.padding, available_w, available_h, env)
    local width_value = resolve_token(env.styles, node.width)
    local height_value = resolve_token(env.styles, node.height)
    local resolved_w = width_value ~= nil and width_value ~= "content"
        and dimension(width_value, available_w, 0, env) or nil
    local resolved_h = height_value ~= nil and height_value ~= "content"
        and dimension(height_value, available_h, 0, env) or nil
    local inner_w = math.max(0, (resolved_w or available_w) - padding.left - padding.right)
    local inner_h = math.max(0, (resolved_h or available_h) - padding.top - padding.bottom)
    local gap = length(node.gap or 0, node.kind == "row" and inner_w or inner_h, env) or 0
    local children = {}
    local content_w, content_h = 0, 0

    for child_index, child in ipairs(node.children or {}) do
        local item = measure(child, inner_w, inner_h, env)
        item.declaration_order = child_index
        children[#children + 1] = item
        if node.kind == "row" then
            content_w = content_w + item.w
            content_h = math.max(content_h, item.h)
        elseif node.kind == "column" then
            content_w = math.max(content_w, item.w)
            content_h = content_h + item.h
        else
            content_w = math.max(content_w, item.w)
            content_h = math.max(content_h, item.h)
        end
    end
    if #children > 1 and node.kind == "row" then content_w = content_w + gap * (#children - 1) end
    if #children > 1 and node.kind == "column" then content_h = content_h + gap * (#children - 1) end
    if node.kind ~= "row" and node.kind ~= "column" then
        table.sort(children, function(left, right)
            local left_z, right_z = tonumber(left.node.z) or 0, tonumber(right.node.z) or 0
            if left_z == right_z then return left.declaration_order < right.declaration_order end
            return left_z < right_z
        end)
    end

    content_w = content_w + padding.left + padding.right
    content_h = content_h + padding.top + padding.bottom
    return {
        kind = node.kind,
        node = node,
        children = children,
        padding = padding,
        gap = gap,
        w = dimension(node.width, available_w, content_w, env),
        h = dimension(node.height, available_h, content_h, env),
    }
end

measure = function(node, available_w, available_h, env)
    assert(type(node) == "table" and node.kind, "ui2d layout received an invalid node")
    env = scoped_environment(node, env)
    local item
    if node.kind == "text" then item = measure_text(node, env)
    elseif node.kind == "icon" then item = measure_icon(node, available_w, available_h, env)
    elseif node.kind == "spacer" then item = measure_spacer(node, available_w, available_h, env)
    elseif node.kind == "button" then item = Button.measure(node, available_w, available_h, env, measure)
    elseif node.kind == "text_field" then item = TextField.measure(node, available_w, available_h, env)
    else item = measure_container(node, available_w, available_h, env) end
    item.styles = env.styles
    item.env = env
    return item
end

local function anchored(parent, width, height, anchor)
    anchor = anchor or "top-left"
    local horizontal = anchor:find("left", 1, true) and "left"
        or (anchor:find("right", 1, true) and "right"
        or (anchor:find("center", 1, true) and "center" or "left"))
    local vertical = anchor:find("bottom", 1, true) and "bottom" or (anchor == "center" or anchor:find("center", 1, true) and not anchor:find("top", 1, true) and not anchor:find("bottom", 1, true)) and "center" or "top"
    local x = horizontal == "right" and parent.x + parent.w - width or (horizontal == "center" and parent.x + (parent.w - width) / 2 or parent.x)
    local y = vertical == "bottom" and parent.y + parent.h - height or (vertical == "center" and parent.y + (parent.h - height) / 2 or parent.y)
    return x, y
end

local arrange

local function content_rect(item)
    local padding = item.padding or {left = 0, right = 0, top = 0, bottom = 0}
    return {
        x = item.rect.x + padding.left,
        y = item.rect.y + padding.top,
        w = math.max(0, item.rect.w - padding.left - padding.right),
        h = math.max(0, item.rect.h - padding.top - padding.bottom),
    }
end

local function flex_main_sizes(item, area, horizontal, result)
    local available = horizontal and area.w or area.h
    local sizes, active = {}, {}
    local remaining = available - item.gap * math.max(0, #item.children - 1)
    for index, child in ipairs(item.children) do
        local flex = math.max(0, tonumber(child.node.flex) or 0)
        if flex > 0 then
            local configured = child.node.flex_basis
            sizes[index] = configured and (length(configured, available, result.env) or 0) or 0
            active[index] = {
                weight = flex,
                minimum = length(horizontal and child.node.min_width or child.node.min_height,
                    available, result.env) or 0,
                maximum = length(horizontal and child.node.max_width or child.node.max_height,
                    available, result.env) or math.huge,
            }
        else
            sizes[index] = horizontal and child.w or child.h
        end
        remaining = remaining - sizes[index]
    end

    while next(active) and math.abs(remaining) > 0.0001 do
        local total_weight = 0
        for _, constraints in pairs(active) do total_weight = total_weight + constraints.weight end
        local clamped = false
        for index, constraints in pairs(active) do
            local proposed = sizes[index] + remaining * constraints.weight / total_weight
            local constrained = math.max(constraints.minimum, math.min(constraints.maximum, proposed))
            if math.abs(constrained - proposed) > 0.0001 then
                remaining = remaining - (constrained - sizes[index])
                sizes[index] = constrained
                active[index] = nil
                clamped = true
            end
        end
        if not clamped then
            for index, constraints in pairs(active) do
                sizes[index] = sizes[index] + remaining * constraints.weight / total_weight
            end
            remaining = 0
        end
    end
    return sizes
end

arrange = function(item, x, y, width, height, result)
    item.rect = {x = x, y = y, w = width or item.w, h = height or item.h}
    item.layout_scale = result.scale
    if item.node.id then
        if result.by_id[item.node.id] then error("duplicate node id in view: " .. item.node.id) end
        result.by_id[item.node.id] = item
    end
    if item.kind == "panel" and item.node.pointer ~= "pass" then
        result.hit_regions[#result.hit_regions + 1] = {item = item, blocks = true}
    end
    if item.interactive then
        result.interactive[#result.interactive + 1] = item
        result.hit_regions[#result.hit_regions + 1] = {item = item, interactive = true}
    end
    local area = content_rect(item)
    if item.kind == "screen" or item.kind == "stack" or item.kind == "panel" then
        for _, child in ipairs(item.children or {}) do
            local child_x, child_y = anchored(area, child.w, child.h, child.node.anchor)
            arrange(child, child_x, child_y, child.w, child.h, result)
        end
    elseif item.kind == "row" or item.kind == "column" then
        local horizontal = item.kind == "row"
        local sizes = flex_main_sizes(item, area, horizontal, result)
        local available = horizontal and area.w or area.h
        local used = item.gap * math.max(0, #item.children - 1)
        local total_flex = 0
        for index, child in ipairs(item.children) do
            used = used + sizes[index]
            total_flex = total_flex + math.max(0, tonumber(child.node.flex) or 0)
        end
        local cursor = (horizontal and area.x or area.y)
        if total_flex == 0 and item.node.justify == "center" then cursor = cursor + (available - used) / 2
        elseif total_flex == 0 and item.node.justify == "end" then cursor = cursor + available - used end
        for index, child in ipairs(item.children) do
            local main_size = sizes[index]
            local child_x, child_y = area.x, area.y
            if horizontal then
                child_x = cursor
                if item.node.align == "center" then child_y = area.y + (area.h - child.h) / 2
                elseif item.node.align == "end" then child_y = area.y + area.h - child.h end
                cursor = cursor + main_size + item.gap
            else
                child_y = cursor
                if item.node.align == "center" then child_x = area.x + (area.w - child.w) / 2
                elseif item.node.align == "end" then child_x = area.x + area.w - child.w end
                cursor = cursor + main_size + item.gap
            end
            arrange(child, child_x, child_y,
                horizontal and main_size or child.w,
                horizontal and child.h or main_size,
                result)
        end
    elseif item.kind == "button" then
        local child = item.children[1]
        arrange(child, area.x + (area.w - child.w) / 2, area.y + (area.h - child.h) / 2, child.w, child.h, result)
    end
end

function Layout.build(root, width, height, env)
    assert(root.kind == "screen", "a ui2d view must return UI.screen")
    env.scale = env.scale or env.styles:viewport_scale(width, height)
    local measured = measure(root, width, height, env)
    measured.w, measured.h = width, height
    local result = {
        root = measured,
        interactive = {},
        hit_regions = {},
        by_id = {},
        scale = env.scale,
        width = width,
        height = height,
        modal = root.modal == true,
        env = env,
    }
    arrange(measured, 0, 0, width, height, result)
    Navigation.build(result)
    Layout.refresh_visuals(result)
    return result
end

function Layout.resolve_visual_transform(item, layout, source)
    if source == nil and item.animated_transform then return item.animated_transform end
    source = source or item.node.transform or (item.style and item.style.transform) or {}
    local scale = source.scale or 1
    local origin_x = source.origin_x == nil and 0.5 or source.origin_x
    local origin_y = source.origin_y == nil and 0.5 or source.origin_y
    return {
        translate_x = length(source.translate_x or source.x or 0, item.rect.w, item.env or layout.env) or 0,
        translate_y = length(source.translate_y or source.y or 0, item.rect.h, item.env or layout.env) or 0,
        scale_x = source.scale_x or scale,
        scale_y = source.scale_y or scale,
        rotation = source.rotation or 0,
        origin_x = item.rect.x + item.rect.w * origin_x,
        origin_y = item.rect.y + item.rect.h * origin_y,
    }
end

local function refresh_item(item, layout, parent_transform)
    item.visual_transform = Layout.resolve_visual_transform(item, layout)
    item.local_transform = Transform.compose(item.visual_transform)
    item.world_transform = Transform.multiply(parent_transform, item.local_transform)
    item.visual_rect = Transform.bounds(item.world_transform, item.rect)
    item.visual_opacity = item.animated_opacity == nil and (item.node.opacity == nil and 1 or item.node.opacity)
        or item.animated_opacity
    for _, child in ipairs(item.children or {}) do
        refresh_item(child, layout, item.world_transform)
    end
end

function Layout.refresh_visuals(layout)
    local parent = Transform.identity()
    if layout.layer_visual_transform then parent = Transform.compose(layout.layer_visual_transform) end
    refresh_item(layout.root, layout, parent)
end

Layout.resolve_length = length

return Layout
