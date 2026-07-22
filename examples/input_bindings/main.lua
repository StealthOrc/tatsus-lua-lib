package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")
local Input = require("input")

local smoke = os.getenv("INPUT_SMOKE") == "1"
local smoke_finished = false
local ui
local last_action = "Move a control to see semantic input here."

local actions = {
    {id = "move", label = "Move (2D)"},
    {id = "vertical", label = "Vertical axis"},
    {id = "horizontal", label = "Horizontal axis"},
    {id = "save", label = "Save chord / button"},
}

local controls = Input.new {
    actions = {
        ui_navigate = {kind = "axis2d"},
        ui_accept = {kind = "button"},
        move = {kind = "axis2d"},
        vertical = {kind = "axis1d"},
        horizontal = {kind = "axis1d"},
        save = {kind = "button"},
    },
    bindings = {
        keyboard = {
            ui_navigate = Input.vector2 {up = "up", down = "down", left = "left", right = "right"},
            ui_accept = {Input.key("return"), Input.key("space")},
            move = Input.vector2 {up = "w", down = "s", left = "a", right = "d"},
            vertical = Input.digital_axis {negative = "w", positive = "s"},
            horizontal = Input.digital_axis {negative = "a", positive = "d"},
            save = Input.chord {"ctrl", "alt", "s"},
        },
        gamepad = {
            ui_navigate = {
                Input.stick("left", {deadzone = 0.3}),
                Input.vector2 {
                    up = Input.gamepad_button("dpup"),
                    down = Input.gamepad_button("dpdown"),
                    left = Input.gamepad_button("dpleft"),
                    right = Input.gamepad_button("dpright"),
                },
            },
            ui_accept = Input.gamepad_button("a"),
            move = Input.stick("left"),
            vertical = Input.axis("lefty"),
            horizontal = Input.axis("righty"),
            save = Input.gamepad_button("y"),
        },
    },
    dispatch = function(event)
        if event.action == "ui_navigate" then
            ui:input {action = "navigate", value = event.value, phase = event.phase, source = event.source}
        elseif event.action == "ui_accept" then
            ui:input {action = "accept", phase = event.phase, source = event.source}
        else
            local value = event.value
            local display = type(value) == "table"
                and string.format("(%.2f, %.2f)", value.x or 0, value.y or 0)
                or string.format("%.2f", value or 0)
            last_action = string.format("%s · %s · %s", event.action, event.phase, display)
        end
    end,
}

local styles = UI.StyleSheet {
    viewport = {reference_width = 1100, reference_height = 720, min_scale = 0.75, max_scale = 2},
    colors = {
        screen = {0.035, 0.045, 0.07, 1},
        panel = {0.075, 0.09, 0.135, 1},
        accent = {0.31, 0.62, 0.96, 1},
        accent_hover = {0.40, 0.71, 1, 1},
        text = {0.94, 0.96, 1, 1},
        muted = {0.62, 0.68, 0.78, 1},
    },
    text = {
        title = {size = 30, color = "text"},
        body = {size = 17, color = "text"},
        small = {size = 14, color = "muted"},
    },
    buttons = {
        binding = {
            background = "panel",
            foreground = "text",
            min_width = 420,
            min_height = 54,
            padding_x = 16,
            padding_y = 10,
            text = "body",
            transform = {scale = 1},
            states = {
                highlighted = {background = "accent_hover", transform = {scale = 1.025}},
                hovered = "highlighted",
                selected = "highlighted",
                pressed = {background = "accent", transform = {scale = 0.985}},
            },
            transition = {transform = {duration = 0.12, ease = "out_cubic"}},
        },
    },
}

local function control_label(control)
    if type(control) == "string" then return control:upper() end
    if control.kind == "key" then return control.key:upper() end
    if control.kind == "gamepad_button" then return control.button:upper() end
    if control.kind == "chord" then
        local parts = {}
        for _, child in ipairs(control.controls or {}) do parts[#parts + 1] = control_label(child) end
        return table.concat(parts, " + ")
    end
    if control.kind == "vector2" then
        return table.concat({control_label(control.up), control_label(control.left),
            control_label(control.down), control_label(control.right)}, "  ")
    end
    if control.kind == "digital_axis" then
        return control_label(control.negative) .. " / " .. control_label(control.positive)
    end
    if control.kind == "stick" then return control.stick:gsub("^%l", string.upper) .. " stick" end
    if control.kind == "axis" then return control.axis .. " axis" end
    if control.kind == "axis_button" then
        return control.axis .. (control.direction == -1 and " −" or " +")
    end
    return control.kind or "unbound"
end

local function prompt(action, scheme)
    local values = controls:prompts(action, scheme)
    local labels = {}
    for _, value in ipairs(values) do labels[#labels + 1] = control_label(value) end
    return #labels > 0 and table.concat(labels, "  /  ") or "Unbound"
end

local function binding_column(scheme, title)
    local children = {UI.text {value = title, style = "body"}}
    for _, action in ipairs(actions) do
        children[#children + 1] = UI.button {
            id = scheme .. "-" .. action.id,
            style = "binding",
            width = "fill",
            label = action.label .. "   ·   " .. prompt(action.id, scheme),
            action = {type = "rebind", input_action = action.id, scheme = scheme},
        }
    end
    return UI.column {flex = 1, gap = 10, children = children}
end

local BindingsView = UI.view("bindings", function()
    local active = controls:active_device()
    local capture = controls:capturing()
    local status = capture
        and ("Listening for a " .. capture.scheme .. " binding for “" .. capture.action .. "”…")
        or ("Active input: " .. active.kind .. " · Select any binding to replace it")
    return UI.screen {
        background = "screen",
        padding = 34,
        UI.column {
            width = "fill",
            gap = 18,
            UI.text {value = "Device-aware input bindings", style = "title"},
            UI.text {value = status, style = capture and "body" or "small"},
            UI.panel {
                width = "fill",
                background = "panel",
                padding = 18,
                pointer = "pass",
                UI.row {
                    width = "fill",
                    gap = 24,
                    binding_column("keyboard", "Keyboard bindings"),
                    binding_column("gamepad", "Controller bindings"),
                },
            },
            UI.text {value = last_action, style = "small"},
            UI.text {
                value = "Arrows/Enter or left stick/D-pad/A navigate this menu through the bindings module.",
                style = "small",
            },
        },
    }
end)

ui = UI.new {
    styles = styles,
    dispatch = function(action)
        if action.type == "rebind" then
            controls:begin_capture(action.input_action, action.scheme)
        end
    end,
}

function love.load()
    ui:show(BindingsView)
    ui:update(0)
end

function love.update(dt)
    controls:update(dt)
    ui:update(dt)
end

function love.draw()
    ui:draw()
    if smoke and not smoke_finished then
        smoke_finished = true
        print("input bindings example smoke passed")
        love.event.quit(0)
    end
end

function love.mousemoved(...) ui:event("mousemoved", ...) end
function love.mousepressed(...) ui:event("mousepressed", ...) end
function love.mousereleased(...) ui:event("mousereleased", ...) end
function love.wheelmoved(...) ui:event("wheelmoved", ...) end
function love.keypressed(...) controls:event("keypressed", ...) end
function love.keyreleased(...) controls:event("keyreleased", ...) end
function love.gamepadpressed(...) controls:event("gamepadpressed", ...) end
function love.gamepadreleased(...) controls:event("gamepadreleased", ...) end
function love.gamepadaxis(...) controls:event("gamepadaxis", ...) end
function love.joystickremoved(...) controls:event("joystickremoved", ...) end
function love.resize(...) ui:event("resize", ...) end
