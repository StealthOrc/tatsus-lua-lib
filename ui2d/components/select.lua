local Nodes = require("ui2d.core.nodes")
local Button = require("ui2d.components.button")
local StyleSheet = require("ui2d.core.style_sheet")

local Select = {}

Nodes.register("select")

local function option_value(option)
    return type(option) == "table" and option.value or option
end

local function option_label(option)
    if type(option) == "table" then
        return option.label or tostring(option.value)
    end
    return tostring(option)
end

local function normalized_groups(node)
    if node.groups then return node.groups end
    return {{options = node.options or {}}}
end

local function selected_label(node)
    for _, group in ipairs(normalized_groups(node)) do
        for _, option in ipairs(group.options or {}) do
            if option_value(option) == node.value then
                return option_label(option)
            end
        end
    end
    return node.placeholder or "Select"
end

local function internal_action(kind, node, option)
    return {
        __ui2d_select = kind,
        control = node.id,
        option = option,
        changed = node.changed or node.action,
    }
end

function Select.new(spec)
    spec = spec or {}
    return Nodes.construct("select", spec)
end

function Select.measure(node, available_w, available_h, env, measure)
    assert(type(node.id) == "string" and node.id ~= "",
        "select requires a non-empty id")
    local groups = normalized_groups(node)
    local option_count = 0
    for _, group in ipairs(groups) do
        option_count = option_count + #(group.options or {})
    end
    assert(option_count > 0, "select requires at least one option")

    local state = env.select_for(node)
    local width = node.width or 280
    local trigger_height = node.height or 44
    local trigger = Button.new {
        id = node.id .. "-trigger",
        width = "fill",
        height = trigger_height,
        style = node.button_style,
        label = selected_label(node)
            .. (state.open and "  ▲" or "  ▼"),
        enabled = node.enabled ~= false,
        action = internal_action("toggle", node),
    }
    local children = {trigger}
    if state.open then
        local entries = {}
        for group_index, group in ipairs(groups) do
            if group.label then
                entries[#entries + 1] = Nodes.text {
                    value = group.label,
                    style = node.heading_style,
                    color = node.heading_color,
                }
            end
            for option_index, option in ipairs(group.options or {}) do
                local value = option_value(option)
                entries[#entries + 1] = Button.new {
                    id = node.id .. "-option-"
                        .. tostring(group_index) .. "-"
                        .. tostring(option_index),
                    width = "fill",
                    height = node.option_height or 38,
                    style = value == node.value
                        and (node.selected_style or node.option_style)
                        or node.option_style,
                    label = option_label(option),
                    action = internal_action("choose", node, option),
                }
            end
        end
        local visible_count = math.max(
            1,
            math.floor(node.visible_count or 7)
        )
        local list_height = node.list_height
            or visible_count * (node.option_height or 38)
        children[#children + 1] = Nodes.panel {
            id = node.id .. "-popup",
            z = 10,
            anchor = "top-left",
            width = "fill",
            height = list_height,
            padding = node.list_padding or 6,
            radius = node.list_radius or node.radius or 7,
            background = node.list_background,
            border = node.list_border,
            border_width = node.list_border_width,
            transform = {
                translate_y = trigger_height + (node.list_gap or 4),
            },
            Nodes.column {
                id = node.id .. "-options",
                width = "fill",
                height = "fill",
                gap = node.option_gap or 2,
                overflow = "auto",
                children = entries,
            },
        }
    end
    local declaration = Nodes.stack {
        id = node.id,
        styles = node.styles,
        width = width,
        height = trigger_height,
        overflow = "visible",
        children = children,
    }
    local item = measure(declaration, available_w, available_h, env)
    item.select_node = node
    return item
end

function Select.handle(context, action, extra, view_key)
    local state = context.selects[view_key]
        and context.selects[view_key][action.control]
    if not state then return false end
    if action.__ui2d_select == "toggle" then
        state.open = not state.open
        return true
    elseif action.__ui2d_select == "choose" then
        state.open = false
        local changed = action.changed
        local result
        if type(changed) == "string" then
            result = {type = changed}
        elseif type(changed) == "table" then
            result = StyleSheet.copy(changed)
        end
        if result then
            result.control = result.control or action.control
            result.source = result.source or action.control
            result.view = result.view or view_key
            result.value = option_value(action.option)
            result.option = action.option
            for key, value in pairs(extra or {}) do
                result[key] = value
            end
            context.actions[#context.actions + 1] = result
        end
        return true
    end
    return false
end

return Select
