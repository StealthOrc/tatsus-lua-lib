local Units = require("ui2d.units")
local Nodes = require("ui2d.nodes")
local Transform = require("ui2d.transform")
local Navigation = require("ui2d.navigation")

local Layout = {}

local function resolve_token(styles, value)
    local seen = {}
    while type(value) == "string" and value ~= "fill" and value ~= "content" do
        if seen[value] then error("cyclic stylesheet token: " .. value) end
        seen[value] = true
        local resolved = styles:get(value)
        if resolved == nil then break end
        value = resolved
    end
    return value
end

local function length(value, available, env, font_size)
    value = resolve_token(env.styles, value)
    return Units.resolve(value, available, {
        scale = env.scale,
        font_size = font_size,
        root_font_size = env.styles.values.root_font_size * env.scale,
    })
end

local function dimension(value, available, content, env, font_size)
    value = resolve_token(env.styles, value)
    if value == nil or value == "content" then return content end
    if value == "fill" then return available end
    return length(value, available, env, font_size)
end

local function insets(value, available_w, available_h, env, font_size)
    value = resolve_token(env.styles, value or 0)
    if type(value) ~= "table" or Units.is(value) then
        local horizontal = length(value, available_w, env, font_size) or 0
        local vertical = length(value, available_h, env, font_size) or 0
        return {left = horizontal, right = horizontal, top = vertical, bottom = vertical}
    end
    local x = value.x or value.horizontal or 0
    local y = value.y or value.vertical or 0
    return {
        left = length(value.left or x, available_w, env, font_size) or 0,
        right = length(value.right or x, available_w, env, font_size) or 0,
        top = length(value.top or y, available_h, env, font_size) or 0,
        bottom = length(value.bottom or y, available_h, env, font_size) or 0,
    }
end

local function overlay_style(style, node)
    for key in pairs(style) do
        if node[key] ~= nil then style[key] = node[key] end
    end
    return style
end

local measure

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

local function shorthand_button_content(node, style, env)
    if node.content then return node.content end
    if #(node.children or {}) > 0 then
        return Nodes.row {gap = style.gap, align = "center", children = node.children}
    end
    local children = {}
    local text_style = node.text_style or style.text
    local resolved_text = env.fonts:text_style(text_style)
    if node.icon then
        children[#children + 1] = Nodes.icon {
            name = node.icon,
            size = node.icon_size or style.icon_size or resolved_text.size * 1.2,
            tint = node.icon_tint or style.foreground,
        }
    end
    if node.label ~= nil then
        children[#children + 1] = Nodes.text {
            value = node.label,
            style = text_style,
            color = node.foreground or style.foreground,
        }
    end
    return Nodes.row {gap = node.gap or style.gap, align = "center", children = children}
end

local function measure_button(node, available_w, available_h, env)
    assert(type(node.id) == "string" and node.id ~= "", "button requires a non-empty id")
    local style = overlay_style(env.styles:button_style(node.style), node)
    local padding = {
        left = length(style.padding_x or 0, available_w, env),
        right = length(style.padding_x or 0, available_w, env),
        top = length(style.padding_y or 0, available_h, env),
        bottom = length(style.padding_y or 0, available_h, env),
    }
    local inner_w = math.max(0, available_w - padding.left - padding.right)
    local inner_h = math.max(0, available_h - padding.top - padding.bottom)
    local content = measure(shorthand_button_content(node, style, env), inner_w, inner_h, env)
    local content_w = content.w + padding.left + padding.right
    local content_h = content.h + padding.top + padding.bottom
    local min_w = length(style.min_width or 0, available_w, env) or 0
    local min_h = length(style.min_height or 0, available_h, env) or 0
    return {
        kind = "button",
        node = node,
        style = style,
        children = {content},
        padding = padding,
        enabled = node.enabled ~= false,
        interactive = true,
        w = math.max(min_w, dimension(node.width, available_w, content_w, env)),
        h = math.max(min_h, dimension(node.height, available_h, content_h, env)),
    }
end

local function measure_text_field(node, available_w, available_h, env)
    assert(type(node.id) == "string" and node.id ~= "", "text_field requires a non-empty id")
    local style = overlay_style(env.styles:text_field_style(node.style), node)
    local text_style = env.fonts:text_style(node.text_style or style.text)
    local font = env.fonts:get(text_style, env.scale)
    local min_w = length(style.min_width or 0, available_w, env) or 0
    local min_h = length(style.min_height or 0, available_h, env) or 0
    return {
        kind = "text_field",
        node = node,
        style = style,
        text_style = text_style,
        font = font,
        editor = env.editor_for(node),
        enabled = node.enabled ~= false,
        interactive = true,
        w = math.max(min_w, dimension(node.width, available_w, min_w, env)),
        h = math.max(min_h, dimension(node.height, available_h, min_h, env)),
    }
end

measure = function(node, available_w, available_h, env)
    assert(type(node) == "table" and node.kind, "ui2d layout received an invalid node")
    if node.kind == "text" then return measure_text(node, env) end
    if node.kind == "icon" then return measure_icon(node, available_w, available_h, env) end
    if node.kind == "spacer" then return measure_spacer(node, available_w, available_h, env) end
    if node.kind == "button" then return measure_button(node, available_w, available_h, env) end
    if node.kind == "text_field" then return measure_text_field(node, available_w, available_h, env) end
    return measure_container(node, available_w, available_h, env)
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
    env.scale = env.styles:viewport_scale(width, height)
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
        translate_x = length(source.translate_x or source.x or 0, item.rect.w, layout.env) or 0,
        translate_y = length(source.translate_y or source.y or 0, item.rect.h, layout.env) or 0,
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
