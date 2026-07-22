package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")
local Input = require("input")
local Game = require("game")
local Views = require("views")

local smoke = os.getenv("INPUT_SMOKE") == "1"
local smoke_finished = false
local game = Game.new()
local ui
local paused = false
local gamepad_mode = "stick"
local input_values = {}
local dash_requested = false

-- This is the part the example is about: independent Binding Sets describe the
-- same intentions with keys, a complete stick, independent axes, or directions.
local action_definitions = {
    ui_navigate = {kind = "axis2d"},
    ui_accept = {kind = "button"},
    pause = {kind = "button"},
    dash = {kind = "button"},

    move_up = {kind = "button"},
    move_down = {kind = "button"},
    move_left = {kind = "button"},
    move_right = {kind = "button"},

    pad_move = {kind = "axis2d"},
    pad_horizontal = {kind = "axis1d"},
    pad_vertical = {kind = "axis1d"},
    pad_up = {kind = "button"},
    pad_down = {kind = "button"},
    pad_left = {kind = "button"},
    pad_right = {kind = "button"},
}

local binding_sets = {
    keyboard = {
        ui_navigate = Input.vector2 {up = "up", down = "down", left = "left", right = "right"},
        ui_accept = {Input.key("return"), Input.key("space")},
        pause = Input.key("escape"),
        dash = Input.key("lshift"),
        move_up = Input.key("w"),
        move_down = Input.key("s"),
        move_left = Input.key("a"),
        move_right = Input.key("d"),
    },
    gamepad = {
        ui_navigate = {
            Input.stick("left", {deadzone = 0.32}),
            Input.vector2 {
                up = Input.gamepad_button("dpup"),
                down = Input.gamepad_button("dpdown"),
                left = Input.gamepad_button("dpleft"),
                right = Input.gamepad_button("dpright"),
            },
        },
        ui_accept = Input.gamepad_button("a"),
        pause = Input.gamepad_button("start"),
        dash = Input.gamepad_button("rightshoulder"),

        pad_move = Input.stick("left", {deadzone = 0.18}),
        pad_horizontal = Input.axis("leftx", {deadzone = 0.18}),
        pad_vertical = Input.axis("lefty", {deadzone = 0.18}),
        pad_up = Input.axis_button("lefty", -1),
        pad_down = Input.axis_button("lefty", 1),
        pad_left = Input.axis_button("leftx", -1),
        pad_right = Input.axis_button("leftx", 1),
    },
}

local set_paused

-- The adapter is deliberately small: UI actions go to UI2D, movement values
-- stay in this game, and neither reusable module imports the other.
local function handle_input(event)
    if event.action == "ui_navigate" then
        if paused then
            ui:input {action = "navigate", value = event.value,
                phase = event.phase, source = event.source}
        end
    elseif event.action == "ui_accept" then
        if paused then
            ui:input {action = "accept", phase = event.phase, source = event.source}
        end
    elseif event.action == "pause" and event.phase == "pressed" then
        set_paused(not paused)
    elseif event.action == "dash" and event.phase == "pressed" then
        if not paused then dash_requested = true end
    else
        input_values[event.action] = event.value
    end
end

local controls = Input.new {
    actions = action_definitions,
    bindings = binding_sets,
    dispatch = handle_input,
}

local keyboard_rows = {
    {action = "move_up", label = "Move up"},
    {action = "move_down", label = "Move down"},
    {action = "move_left", label = "Move left"},
    {action = "move_right", label = "Move right"},
    {action = "dash", label = "Dash"},
    {action = "pause", label = "Pause / controls"},
}

local gamepad_rows = {
    stick = {
        {action = "pad_move", label = "Move"},
        {action = "dash", label = "Dash"},
        {action = "pause", label = "Pause / controls"},
    },
    axes = {
        {action = "pad_horizontal", label = "Horizontal movement"},
        {action = "pad_vertical", label = "Vertical movement"},
        {action = "dash", label = "Dash"},
        {action = "pause", label = "Pause / controls"},
    },
    directions = {
        {action = "pad_up", label = "Move up"},
        {action = "pad_down", label = "Move down"},
        {action = "pad_left", label = "Move left"},
        {action = "pad_right", label = "Move right"},
        {action = "dash", label = "Dash"},
        {action = "pause", label = "Pause / controls"},
    },
}

local button_names = {
    a = "A", b = "B", x = "X", y = "Y", start = "START", back = "BACK",
    dpup = "D-PAD UP", dpdown = "D-PAD DOWN",
    dpleft = "D-PAD LEFT", dpright = "D-PAD RIGHT",
    leftshoulder = "LB / L1", rightshoulder = "RB / R1",
}

local axis_names = {
    leftx = "LEFT X", lefty = "LEFT Y", rightx = "RIGHT X", righty = "RIGHT Y",
}

local key_names = {
    lshift = "LEFT SHIFT", rshift = "RIGHT SHIFT",
    escape = "ESCAPE", space = "SPACE", ["return"] = "ENTER",
}

local function control_label(control)
    if type(control) == "string" then return control:upper() end
    if control.kind == "key" then return key_names[control.key] or control.key:upper() end
    if control.kind == "gamepad_button" then
        return button_names[control.button] or control.button:upper()
    end
    if control.kind == "chord" then
        local parts = {}
        for _, child in ipairs(control.controls or {}) do parts[#parts + 1] = control_label(child) end
        return table.concat(parts, " + ")
    end
    if control.kind == "stick" then return control.stick:upper() .. " STICK" end
    if control.kind == "axis" then return axis_names[control.axis] or control.axis:upper() end
    if control.kind == "axis_button" then
        local axis = axis_names[control.axis] or control.axis:upper()
        local direction
        if control.axis:sub(-1) == "x" then direction = control.direction < 0 and "LEFT" or "RIGHT"
        else direction = control.direction < 0 and "UP" or "DOWN" end
        return axis .. " · " .. direction
    end
    if control.kind == "digital_axis" then
        return control_label(control.negative) .. " / " .. control_label(control.positive)
    end
    if control.kind == "vector2" then
        return table.concat({control_label(control.up), control_label(control.left),
            control_label(control.down), control_label(control.right)}, " · ")
    end
    return control.kind and control.kind:upper() or "UNBOUND"
end

local function prompt(action, scheme)
    local labels = {}
    for _, binding in ipairs(controls:prompts(action, scheme)) do
        labels[#labels + 1] = control_label(binding)
    end
    return #labels > 0 and table.concat(labels, "  /  ") or "UNBOUND"
end

local function active_scheme()
    return controls:active_device().kind == "gamepad" and "gamepad" or "keyboard"
end

local function movement_vector()
    if active_scheme() == "keyboard" then
        return {
            x = (input_values.move_right or 0) - (input_values.move_left or 0),
            y = (input_values.move_down or 0) - (input_values.move_up or 0),
        }
    elseif gamepad_mode == "stick" then
        return input_values.pad_move or {x = 0, y = 0}
    elseif gamepad_mode == "axes" then
        return {x = input_values.pad_horizontal or 0, y = input_values.pad_vertical or 0}
    end
    return {
        x = (input_values.pad_right or 0) - (input_values.pad_left or 0),
        y = (input_values.pad_down or 0) - (input_values.pad_up or 0),
    }
end

local function pause_model()
    local scheme = active_scheme()
    local source_rows = scheme == "gamepad" and gamepad_rows[gamepad_mode] or keyboard_rows
    local rows = {}
    for _, row in ipairs(source_rows) do
        rows[#rows + 1] = {
            action = row.action,
            label = row.label,
            binding = prompt(row.action, scheme),
            scheme = scheme,
        }
    end
    local capture = controls:capturing()
    local capture_text
    if capture then
        capture_text = "LISTENING · Press the new " .. capture.scheme:upper() .. " input for “"
            .. capture.action:gsub("_", " "):upper() .. "”"
    end
    return {
        scheme = scheme,
        device_label = scheme == "gamepad" and "GAMEPAD" or "KEYBOARD + MOUSE",
        gamepad_mode = gamepad_mode,
        rows = rows,
        capture = capture_text,
        footer_hint = scheme == "gamepad"
            and "START resumes · Left stick / D-pad navigates · A selects"
            or "ESC resumes · Arrow keys navigate · Enter selects",
    }
end

local function hud_model()
    local status = game:status()
    local scheme = active_scheme()
    status.pause_hint = scheme == "gamepad" and "START · CONTROLS" or "ESC · CONTROLS"
    status.device_label = scheme == "gamepad"
        and ("GAMEPAD · " .. gamepad_mode:upper()) or "KEYBOARD · WASD"
    status.dash_hint = prompt("dash", scheme) .. " · DASH"
    status.dash_color = status.dash_ready and "accent" or "muted"
    return status
end

local pause_transition = {
    from = {opacity = 0, transform = {scale = 0.975}},
    to = {opacity = 1, transform = {scale = 1}},
    duration = 0.16,
    ease = "out_cubic",
}

ui = UI.new {
    styles = Views.styles,
    dispatch = function(action)
        if action.type == "resume" then
            set_paused(false)
        elseif action.type == "set_gamepad_mode" then
            gamepad_mode = action.value
        elseif action.type == "rebind" then
            controls:begin_capture(action.input_action, action.scheme)
        end
    end,
}

set_paused = function(value)
    if paused == value then return end
    paused = value
    if paused then
        ui:push(Views.pause, {
            key = "controls",
            layer = "overlay",
            model = pause_model,
            transition = pause_transition,
        })
    else
        controls:cancel_capture()
        ui:remove("controls")
    end
end

function love.load()
    local width, height = love.graphics.getDimensions()
    game:reset(width, height)
    ui:show(Views.hud, {
        key = "hud",
        layer = "base",
        pointer = "pass",
        keyboard = "pass",
        navigation = "pass",
        model = hud_model,
    })
    if smoke then set_paused(true) end
    ui:update(0)
end

function love.update(dt)
    controls:update(dt)
    if not paused then
        local movement = movement_vector()
        if dash_requested and game:dash(movement) then dash_requested = false end
        game:update(dt, movement)
    else
        dash_requested = false
    end
    ui:update(dt)
end

function love.draw()
    game:draw()
    ui:draw()
    if smoke and not smoke_finished then
        smoke_finished = true
        print("input bindings color rite smoke passed")
        love.event.quit(0)
    end
end

function love.mousemoved(...)
    controls:set_active_device("keyboard")
    ui:event("mousemoved", ...)
end

function love.mousepressed(...)
    controls:set_active_device("keyboard")
    ui:event("mousepressed", ...)
end

function love.mousereleased(...) ui:event("mousereleased", ...) end
function love.wheelmoved(...) ui:event("wheelmoved", ...) end
function love.keypressed(...) controls:event("keypressed", ...) end
function love.keyreleased(...) controls:event("keyreleased", ...) end
function love.gamepadpressed(...) controls:event("gamepadpressed", ...) end
function love.gamepadreleased(...) controls:event("gamepadreleased", ...) end
function love.gamepadaxis(...) controls:event("gamepadaxis", ...) end
function love.joystickremoved(...) controls:event("joystickremoved", ...) end

function love.resize(width, height)
    game:resize(width, height)
    ui:event("resize", width, height)
end
