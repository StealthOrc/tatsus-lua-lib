local Context = require("ui2d.context")
local Nodes = require("ui2d.nodes")
local StyleSheetModule = require("ui2d.style_sheet")
local TextEditor = require("ui2d.text_editor")
local Units = require("ui2d.units")

local UI = {
    TextEditor = TextEditor,
    percent = Units.percent,
    em = Units.em,
    rem = Units.rem,
    view = Nodes.view,
    screen = Nodes.screen,
    row = Nodes.row,
    column = Nodes.column,
    stack = Nodes.stack,
    text = Nodes.text,
    icon = Nodes.icon,
    spacer = Nodes.spacer,
    button = Nodes.button,
    text_field = Nodes.text_field,
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
