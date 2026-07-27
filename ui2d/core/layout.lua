local Transform = require("ui2d.core.transform")
local Navigation = require("ui2d.core.navigation")
local LayoutValues = require("ui2d.core.layout_values")
local Button = require("ui2d.components.button")
local TextField = require("ui2d.components.text_field")
local Slider = require("ui2d.components.slider")
local Select = require("ui2d.components.select")

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

local function ellipsize(font, text, maximum_width)
    local suffix = "…"
    if font:getWidth(text) <= maximum_width then return text end
    while text ~= "" and font:getWidth(text .. suffix) > maximum_width do
        text = text:sub(1, -2)
    end
    return text .. suffix
end

local function measure_text(node, available_w, env)
    local text = tostring(node.value or "")
    local natural_width, natural_height, font, style =
        env.fonts:measure(text, node.style or node.text_style, env.scale)
    local width_value = resolve_token(env.styles, node.width)
    local explicit_width = width_value ~= nil and width_value ~= "content"
        and dimension(width_value, available_w, natural_width, env)
        or nil
    local maximum_width = node.max_width
        and length(node.max_width, available_w, env)
        or available_w
    local wrap_width = math.max(1, math.min(
        available_w,
        explicit_width or maximum_width
    ))
    local lines = {text}
    local measured_width = natural_width
    if node.wrap or explicit_width or node.max_width then
        measured_width, lines = font:getWrap(text, wrap_width)
    end
    local max_lines = node.max_lines and math.max(
        1,
        math.floor(node.max_lines)
    ) or nil
    if max_lines and #lines > max_lines then
        while #lines > max_lines do table.remove(lines) end
        if node.overflow == "ellipsis" then
            lines[#lines] = ellipsize(
                font,
                lines[#lines],
                wrap_width
            )
        end
    end
    local line_advance = natural_height * font:getLineHeight()
    local height = #lines == 0 and 0
        or natural_height + math.max(0, #lines - 1) * line_advance
    return {
        kind = "text",
        node = node,
        text = text,
        lines = lines,
        line_advance = line_advance,
        font = font,
        text_style = style,
        w = explicit_width or math.min(measured_width, wrap_width),
        h = height,
    }
end

local function measure_media(kind, node, available_w, available_h, env)
    local name = assert(node.name or node.source,
        kind .. " requires a name")
    local source_w, source_h = env.media:dimensions(name, node)
    local ratio = source_w / math.max(1, source_h)
    local size = node.size and length(
        node.size,
        math.min(available_w, available_h),
        env
    ) or nil
    local width_value = node.width or size
    local height_value = node.height or size
    local width = width_value
        and dimension(width_value, available_w, source_w * env.scale, env)
        or nil
    local height = height_value
        and dimension(height_value, available_h, source_h * env.scale, env)
        or nil

    if width and not height then
        height = width / math.max(0.000001, ratio)
    elseif height and not width then
        width = height * ratio
    elseif not width and not height then
        width, height = source_w * env.scale, source_h * env.scale
    end

    if node.fit ~= "none" then
        local shrink = math.min(
            1,
            available_w / math.max(1, width),
            available_h / math.max(1, height)
        )
        width, height = width * shrink, height * shrink
    end
    return {
        kind = kind,
        node = node,
        media_name = name,
        source_w = source_w,
        source_h = source_h,
        w = math.max(0, width),
        h = math.max(0, height),
    }
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
    local flex_minimum_main = 0
    local has_flex = false

    local flow_line_width = 0
    local flow_line_height = 0
    for child_index, child in ipairs(node.children or {}) do
        local item = measure(child, inner_w, inner_h, env)
        item.declaration_order = child_index
        children[#children + 1] = item
        local child_flex = math.max(0, tonumber(child.flex) or 0)
        if child_flex > 0
            and (node.kind == "row" or node.kind == "column")
        then
            has_flex = true
            flex_minimum_main = flex_minimum_main + (
                length(
                    node.kind == "row"
                        and child.min_width
                        or child.min_height,
                    node.kind == "row" and inner_w or inner_h,
                    env
                ) or 0
            )
        elseif node.kind == "row" then
            flex_minimum_main = flex_minimum_main + item.w
        elseif node.kind == "column" then
            flex_minimum_main = flex_minimum_main + item.h
        end
        if node.kind == "row" then
            content_w = content_w + item.w
            content_h = math.max(content_h, item.h)
        elseif node.kind == "column" then
            content_w = math.max(content_w, item.w)
            content_h = content_h + item.h
        elseif node.kind == "flow" then
            local next_width = flow_line_width
                + (flow_line_width > 0 and gap or 0)
                + item.w
            if flow_line_width > 0 and next_width > inner_w then
                content_w = math.max(content_w, flow_line_width)
                content_h = content_h
                    + (content_h > 0 and gap or 0)
                    + flow_line_height
                flow_line_width = item.w
                flow_line_height = item.h
            else
                flow_line_width = next_width
                flow_line_height = math.max(flow_line_height, item.h)
            end
        else
            content_w = math.max(content_w, item.w)
            content_h = math.max(content_h, item.h)
        end
    end
    if node.kind == "flow" and #children > 0 then
        content_w = math.max(content_w, flow_line_width)
        content_h = content_h
            + (content_h > 0 and gap or 0)
            + flow_line_height
    end
    if #children > 1 and node.kind == "row" then content_w = content_w + gap * (#children - 1) end
    if #children > 1 and node.kind == "column" then content_h = content_h + gap * (#children - 1) end
    if has_flex and node.kind == "row" then
        content_w = math.max(
            inner_w,
            flex_minimum_main + gap * math.max(0, #children - 1)
        )
    elseif has_flex and node.kind == "column" then
        content_h = math.max(
            inner_h,
            flex_minimum_main + gap * math.max(0, #children - 1)
        )
    end
    if node.kind ~= "row" and node.kind ~= "column" then
        table.sort(children, function(left, right)
            local left_z, right_z = tonumber(left.node.z) or 0, tonumber(right.node.z) or 0
            if left_z == right_z then return left.declaration_order < right.declaration_order end
            return left_z < right_z
        end)
    end

    local inner_content_w, inner_content_h = content_w, content_h
    content_w = content_w + padding.left + padding.right
    content_h = content_h + padding.top + padding.bottom
    local overflow = node.overflow
    if overflow == nil then
        overflow = (
            resolved_w
            or resolved_h
            or node.max_width
            or node.max_height
        ) and "auto" or "visible"
    end
    assert(
        overflow == "visible"
            or overflow == "hidden"
            or overflow == "auto"
            or overflow == "scroll",
        "overflow must be visible, hidden, auto, or scroll"
    )
    local measured_w = dimension(node.width, available_w, content_w, env)
    local measured_h = dimension(node.height, available_h, content_h, env)
    if node.min_width then
        measured_w = math.max(
            measured_w,
            length(node.min_width, available_w, env)
        )
    end
    if node.max_width then
        measured_w = math.min(
            measured_w,
            length(node.max_width, available_w, env)
        )
    end
    if node.min_height then
        measured_h = math.max(
            measured_h,
            length(node.min_height, available_h, env)
        )
    end
    if node.max_height then
        measured_h = math.min(
            measured_h,
            length(node.max_height, available_h, env)
        )
    end
    return {
        kind = node.kind,
        node = node,
        children = children,
        padding = padding,
        gap = gap,
        overflow = overflow,
        inner_content_w = inner_content_w,
        inner_content_h = inner_content_h,
        scroll_state = env.scroll_for
            and node.id
            and env.scroll_for(node)
            or nil,
        w = measured_w,
        h = measured_h,
    }
end

measure = function(node, available_w, available_h, env)
    assert(type(node) == "table" and node.kind, "ui2d layout received an invalid node")
    env = scoped_environment(node, env)
    local item
    if node.kind == "text" then item = measure_text(node, available_w, env)
    elseif node.kind == "icon" or node.kind == "image" then
        item = measure_media(node.kind, node, available_w, available_h, env)
    elseif node.kind == "spacer" then item = measure_spacer(node, available_w, available_h, env)
    elseif node.kind == "button" then item = Button.measure(node, available_w, available_h, env, measure)
    elseif node.kind == "text_field" then item = TextField.measure(node, available_w, available_h, env)
    elseif node.kind == "slider" then
        item = Slider.measure(node, available_w, available_h, env)
    elseif node.kind == "select" then
        item = Select.measure(
            node,
            available_w,
            available_h,
            env,
            measure
        )
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

local function intersection(left, right)
    if not left then return right end
    if not right then return left end
    local x = math.max(left.x, right.x)
    local y = math.max(left.y, right.y)
    local right_edge = math.min(left.x + left.w, right.x + right.w)
    local bottom_edge = math.min(left.y + left.h, right.y + right.h)
    return {
        x = x,
        y = y,
        w = math.max(0, right_edge - x),
        h = math.max(0, bottom_edge - y),
    }
end

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

arrange = function(item, x, y, width, height, result, inherited_clip)
    item.rect = {x = x, y = y, w = width or item.w, h = height or item.h}
    item.layout_scale = result.scale
    item.clip_rect = inherited_clip and {
        x = inherited_clip.x,
        y = inherited_clip.y,
        w = inherited_clip.w,
        h = inherited_clip.h,
    } or nil
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
    local scroll_x, scroll_y = 0, 0
    if item.overflow and item.overflow ~= "visible" then
        item.clip_rect = intersection(inherited_clip, area)
        item.scroll_max_x = math.max(
            0,
            (item.inner_content_w or area.w) - area.w
        )
        item.scroll_max_y = math.max(
            0,
            (item.inner_content_h or area.h) - area.h
        )
        local state = item.scroll_state or {x = 0, y = 0}
        state.x = math.max(
            0,
            math.min(item.scroll_max_x, state.x or 0)
        )
        state.y = math.max(
            0,
            math.min(item.scroll_max_y, state.y or 0)
        )
        item.scroll_x, item.scroll_y = state.x, state.y
        scroll_x, scroll_y = state.x, state.y
        if item.node.id and (
            item.overflow == "scroll"
                or item.scroll_max_x > 0
                or item.scroll_max_y > 0
        ) then
            result.scrollable[#result.scrollable + 1] = item
        end
    end
    if item.kind == "screen" or item.kind == "stack" or item.kind == "panel" then
        for _, child in ipairs(item.children or {}) do
            local child_x, child_y = anchored(area, child.w, child.h, child.node.anchor)
            arrange(
                child,
                child_x - scroll_x,
                child_y - scroll_y,
                child.w,
                child.h,
                result,
                item.clip_rect
            )
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
        local cursor = (horizontal and area.x - scroll_x
            or area.y - scroll_y)
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
                result,
                item.clip_rect)
        end
    elseif item.kind == "flow" then
        local cursor_x = area.x - scroll_x
        local cursor_y = area.y - scroll_y
        local line_height = 0
        for _, child in ipairs(item.children or {}) do
            if cursor_x > area.x - scroll_x
                and cursor_x + child.w > area.x - scroll_x + area.w
            then
                cursor_x = area.x - scroll_x
                cursor_y = cursor_y + line_height + item.gap
                line_height = 0
            end
            arrange(
                child,
                cursor_x,
                cursor_y,
                child.w,
                child.h,
                result,
                item.clip_rect
            )
            cursor_x = cursor_x + child.w + item.gap
            line_height = math.max(line_height, child.h)
        end
    elseif item.kind == "button" then
        local child = item.children[1]
        arrange(
            child,
            area.x + (area.w - child.w) / 2,
            area.y + (area.h - child.h) / 2,
            child.w,
            child.h,
            result,
            item.clip_rect
        )
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
        scrollable = {},
        by_id = {},
        scale = env.scale,
        width = width,
        height = height,
        modal = root.modal == true,
        env = env,
    }
    arrange(measured, 0, 0, width, height, result, nil)
    Layout.position_tooltips(result)
    Navigation.build(result)
    Layout.refresh_visuals(result)
    return result
end

local function shift_tree(item, dx, dy)
    item.rect.x, item.rect.y = item.rect.x + dx, item.rect.y + dy
    if item.clip_rect then
        item.clip_rect.x = item.clip_rect.x + dx
        item.clip_rect.y = item.clip_rect.y + dy
    end
    for _, child in ipairs(item.children or {}) do
        shift_tree(child, dx, dy)
    end
end

local function placement_position(name, target, tooltip, gap)
    if name == "left" then
        return target.x - tooltip.w - gap,
            target.y + (target.h - tooltip.h) / 2
    elseif name == "right" then
        return target.x + target.w + gap,
            target.y + (target.h - tooltip.h) / 2
    elseif name == "top" then
        return target.x + (target.w - tooltip.w) / 2,
            target.y - tooltip.h - gap
    end
    return target.x + (target.w - tooltip.w) / 2,
        target.y + target.h + gap
end

local function fits(x, y, item, width, height, margin)
    return x >= margin
        and y >= margin
        and x + item.rect.w <= width - margin
        and y + item.rect.h <= height - margin
end

local function resolve_target(layout, value)
    if type(value) == "string" then
        local item = layout.by_id[value]
        return item and item.visual_rect or item and item.rect
    elseif type(value) == "function" then
        return value(layout)
    end
    return value
end

function Layout.position_tooltips(layout)
    local placements = {"right", "left", "bottom", "top"}
    for _, item in pairs(layout.by_id) do
        local options = item.node.tooltip
        if options then
            local target = assert(
                resolve_target(layout, options.target),
                "tooltip target was not found"
            )
            local margin = options.margin or 12
            local gap = options.gap or 10
            local x, y
            if type(options.place) == "function" then
                local placed = options.place {
                    target = target,
                    tooltip = {
                        w = item.rect.w,
                        h = item.rect.h,
                    },
                    viewport = {
                        x = 0,
                        y = 0,
                        w = layout.width,
                        h = layout.height,
                    },
                    placement = options.placement,
                }
                if type(placed) == "table" then
                    x, y = placed.x, placed.y
                else
                    x, y = placed
                end
            else
                local preferred = options.placement or "auto"
                local candidates = {}
                if preferred ~= "auto" then
                    candidates[#candidates + 1] = preferred
                end
                for _, name in ipairs(placements) do
                    if name ~= preferred then
                        candidates[#candidates + 1] = name
                    end
                end
                if options.collision == "none" then
                    x, y = placement_position(
                        candidates[1],
                        target,
                        item.rect,
                        gap
                    )
                else
                    for _, name in ipairs(candidates) do
                        local candidate_x, candidate_y =
                            placement_position(
                                name,
                                target,
                                item.rect,
                                gap
                            )
                        if fits(
                            candidate_x,
                            candidate_y,
                            item,
                            layout.width,
                            layout.height,
                            margin
                        ) then
                            x, y = candidate_x, candidate_y
                            break
                        end
                    end
                    if not x then
                        x, y = placement_position(
                            candidates[1],
                            target,
                            item.rect,
                            gap
                        )
                    end
                    x = math.max(
                        margin,
                        math.min(
                            layout.width - item.rect.w - margin,
                            x
                        )
                    )
                    y = math.max(
                        margin,
                        math.min(
                            layout.height - item.rect.h - margin,
                            y
                        )
                    )
                end
            end
            assert(type(x) == "number" and type(y) == "number",
                "tooltip placement must return x and y")
            shift_tree(item, x - item.rect.x, y - item.rect.y)
        end
    end
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
