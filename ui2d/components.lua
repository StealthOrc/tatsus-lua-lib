local Nodes = require("ui2d.nodes")
local StyleSheet = require("ui2d.style_sheet")
local Units = require("ui2d.units")

local Components = {}

local function option_value(option)
    return type(option) == "table" and option.value or option
end

local function option_label(option)
    if type(option) == "table" then return option.label or tostring(option.value) end
    return tostring(option)
end

local function changed_action(action, id, value, index)
    local result
    if type(action) == "string" then
        result = {type = action}
    elseif type(action) == "table" then
        result = StyleSheet.copy(action)
    else
        return nil
    end
    result.control = result.control or id
    result.value = value
    result.index = index
    return result
end

function Components.segmented_control(spec)
    spec = spec or {}
    assert(type(spec.id) == "string" and spec.id ~= "",
        "segmented_control requires a non-empty id")
    assert(type(spec.options) == "table" and #spec.options >= 2,
        "segmented_control requires at least two options")

    local selected = 1
    for index, option in ipairs(spec.options) do
        if option_value(option) == spec.value then selected = index break end
    end

    local buttons = {}
    for index, option in ipairs(spec.options) do
        local value = option_value(option)
        buttons[#buttons + 1] = Nodes.button {
            id = spec.id .. "-" .. tostring(value),
            flex = 1,
            height = "fill",
            style = index == selected
                and (spec.selected_style or spec.button_style)
                or spec.button_style,
            label = option_label(option),
            enabled = spec.enabled ~= false,
            action = changed_action(spec.changed or spec.action, spec.id, value, index),
        }
    end

    return Nodes.stack {
        id = spec.id,
        width = spec.width or "fill",
        height = spec.height or 46,
        padding = spec.padding == nil and 3 or spec.padding,
        radius = spec.radius or 8,
        background = spec.background,
        Nodes.panel {
            id = spec.id .. "-indicator",
            z = 0,
            anchor = "top-left",
            pointer = "pass",
            width = Units.percent(1 / #spec.options),
            height = "fill",
            radius = spec.indicator_radius or spec.radius or 6,
            background = spec.indicator_background,
            transform = {translate_x = Units.percent(selected - 1)},
            transition = {
                transform = spec.transition or {duration = 0.16, ease = "out_cubic"},
            },
        },
        Nodes.row {
            z = 1,
            width = "fill",
            height = "fill",
            gap = 0,
            navigation = spec.navigation,
            children = buttons,
        },
    }
end

return Components
