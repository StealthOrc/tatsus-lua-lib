local Nodes = require("ui2d.core.nodes")
local Button = require("ui2d.components.button")

local Modal = {}

function Modal.new(spec)
    spec = spec or {}
    assert(type(spec.id) == "string" and spec.id ~= "",
        "modal requires a non-empty id")
    local panel_children = {}
    local content = spec.content or spec.children
    if content then
        panel_children[#panel_children + 1] = content.kind
            and content
            or Nodes.column {gap = spec.gap or 12, children = content}
    end
    if spec.actions and #spec.actions > 0 then
        local buttons = {}
        for index, action in ipairs(spec.actions) do
            buttons[#buttons + 1] = Button.new {
                id = action.id or spec.id .. "-action-" .. index,
                style = action.style or spec.button_style,
                label = action.label,
                enabled = action.enabled ~= false,
                action = action.action or action.value,
            }
        end
        panel_children[#panel_children + 1] = Nodes.row {
            width = "fill",
            justify = spec.action_justify or "end",
            gap = spec.action_gap or 10,
            children = buttons,
        }
    end
    return Nodes.screen {
        id = spec.id,
        modal = true,
        styles = spec.styles,
        background = spec.veil,
        navigation = {
            entry = spec.initial,
            wrap = spec.wrap ~= false,
        },
        Nodes.column {
            id = spec.id .. "-panel",
            anchor = spec.anchor or "center",
            width = spec.width or "content",
            height = spec.height or "content",
            max_width = spec.max_width,
            max_height = spec.max_height,
            padding = spec.padding or 20,
            gap = spec.gap or 12,
            radius = spec.radius or 10,
            background = spec.background,
            border = spec.border,
            border_width = spec.border_width,
            children = panel_children,
        },
    }
end

return Modal
