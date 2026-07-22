local Context = require("ui2d.core.context")
local Nodes = require("ui2d.core.nodes")
local StyleSheetModule = require("ui2d.core.style_sheet")
local Units = require("ui2d.core.units")
local Button = require("ui2d.components.button")
local TextField = require("ui2d.components.text_field")
local SegmentedControl = require("ui2d.components.segmented_control")

local UI = {
    TextEditor = TextField.Editor,
    percent = Units.percent,
    em = Units.em,
    rem = Units.rem,
    px = Units.px,
    view = Nodes.view,
    screen = Nodes.screen,
    row = Nodes.row,
    column = Nodes.column,
    stack = Nodes.stack,
    panel = Nodes.panel,
    text = Nodes.text,
    icon = Nodes.icon,
    spacer = Nodes.spacer,
    button = Button.new,
    text_field = TextField.new,
    segmented_control = SegmentedControl.new,
}

UI.StyleSheet = setmetatable({new = StyleSheetModule.new}, {
    __call = function(_, config)
        return StyleSheetModule.new(config)
    end,
})

function UI.new(config)
    return Context.new(config)
end

return UI
