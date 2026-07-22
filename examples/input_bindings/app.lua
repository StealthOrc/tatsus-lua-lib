local UI = require("ui2d")
local Input = require("input")
local Game = require("game")
local Styles = require("views.styles")
local HudView = require("views.hud")
local ControlsView = require("views.controls")

local App = {}
App.__index = App

-- Independent Binding Sets describe the same intentions with keys, a complete
-- stick, independent axes, or directions. This is the core of the example.
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

local pause_transition = {
    from = {opacity = 0, transform = {scale = 0.975}},
    to = {opacity = 1, transform = {scale = 1}},
    duration = 0.16,
    ease = "out_cubic",
}

local function control_label(control)
    if type(control) == "string" then return control:upper() end
    if control.kind == "key" then return key_names[control.key] or control.key:upper() end
    if control.kind == "gamepad_button" then
        return button_names[control.button] or control.button:upper()
    end
    if control.kind == "chord" then
        local parts = {}
        for _, child in ipairs(control.controls or {}) do
            parts[#parts + 1] = control_label(child)
        end
        return table.concat(parts, " + ")
    end
    if control.kind == "stick" then return control.stick:upper() .. " STICK" end
    if control.kind == "axis" then return axis_names[control.axis] or control.axis:upper() end
    if control.kind == "axis_button" then
        local axis = axis_names[control.axis] or control.axis:upper()
        local direction
        if control.axis:sub(-1) == "x" then
            direction = control.direction < 0 and "LEFT" or "RIGHT"
        else
            direction = control.direction < 0 and "UP" or "DOWN"
        end
        return axis .. " · " .. direction
    end
    if control.kind == "digital_axis" then
        return control_label(control.negative) .. " / " .. control_label(control.positive)
    end
    if control.kind == "vector2" then
        return table.concat({
            control_label(control.up),
            control_label(control.left),
            control_label(control.down),
            control_label(control.right),
        }, " · ")
    end
    return control.kind and control.kind:upper() or "UNBOUND"
end

function App.new()
    local self = setmetatable({
        smoke = os.getenv("INPUT_SMOKE") == "1",
        smoke_finished = false,
        game = Game.new(),
        paused = false,
        gamepad_mode = "stick",
        input_values = {},
        dash_requested = false,
    }, App)

    self.controls = Input.new {
        actions = action_definitions,
        bindings = binding_sets,
        dispatch = function(event) self:handle_input(event) end,
    }

    self.ui = UI.new {
        styles = Styles,
        dispatch = function(action) self:dispatch(action) end,
    }

    return self
end

function App:load()
    local width, height = love.graphics.getDimensions()
    self.game:reset(width, height)
    self.ui:show(HudView, {
        key = "hud",
        layer = "base",
        pointer = "pass",
        keyboard = "pass",
        navigation = "pass",
        model = function() return self:hud_model() end,
    })
    if self.smoke then self:set_paused(true) end
    self.ui:update(0)
end

function App:update(dt)
    self.controls:update(dt)
    if not self.paused then
        local movement = self:movement_vector()
        if self.dash_requested and self.game:dash(movement) then
            self.dash_requested = false
        end
        self.game:update(dt, movement)
    else
        self.dash_requested = false
    end
    self.ui:update(dt)
end

function App:draw()
    self.game:draw()
    self.ui:draw()
    if self.smoke and not self.smoke_finished then
        self.smoke_finished = true
        print("input bindings color rite smoke passed")
        love.event.quit(0)
    end
end

function App:event(name, ...)
    self.ui:event(name, ...)
end

function App:input_event(name, ...)
    self.controls:event(name, ...)
end

function App:mousemoved(...)
    self.controls:set_active_device("keyboard")
    self.ui:event("mousemoved", ...)
end

function App:mousepressed(...)
    self.controls:set_active_device("keyboard")
    self.ui:event("mousepressed", ...)
end

function App:resize(width, height)
    self.game:resize(width, height)
    self.ui:event("resize", width, height)
end

-- Input actions are adapted here: UI actions go to UI2D while movement values
-- remain inside the demo. Neither reusable library needs to import the other.
function App:handle_input(event)
    if event.action == "ui_navigate" then
        if self.paused then
            self.ui:input {
                action = "navigate",
                value = event.value,
                phase = event.phase,
                source = event.source,
            }
        end
    elseif event.action == "ui_accept" then
        if self.paused then
            self.ui:input {action = "accept", phase = event.phase, source = event.source}
        end
    elseif event.action == "pause" and event.phase == "pressed" then
        self:set_paused(not self.paused)
    elseif event.action == "dash" and event.phase == "pressed" then
        if not self.paused then self.dash_requested = true end
    else
        self.input_values[event.action] = event.value
    end
end

function App:dispatch(action)
    if action.type == "resume" then
        self:set_paused(false)
    elseif action.type == "set_gamepad_mode" then
        self.gamepad_mode = action.value
    elseif action.type == "rebind" then
        self.controls:begin_capture(action.input_action, action.scheme)
    end
end

function App:set_paused(value)
    if self.paused == value then return end
    self.paused = value
    if self.paused then
        self.ui:push(ControlsView, {
            key = "controls",
            layer = "overlay",
            model = function() return self:controls_model() end,
            transition = pause_transition,
        })
    else
        self.controls:cancel_capture()
        self.ui:remove("controls")
    end
end

function App:prompt(action, scheme)
    local labels = {}
    for _, binding in ipairs(self.controls:prompts(action, scheme)) do
        labels[#labels + 1] = control_label(binding)
    end
    return #labels > 0 and table.concat(labels, "  /  ") or "UNBOUND"
end

function App:active_scheme()
    return self.controls:active_device().kind == "gamepad" and "gamepad" or "keyboard"
end

function App:movement_vector()
    if self:active_scheme() == "keyboard" then
        return {
            x = (self.input_values.move_right or 0) - (self.input_values.move_left or 0),
            y = (self.input_values.move_down or 0) - (self.input_values.move_up or 0),
        }
    elseif self.gamepad_mode == "stick" then
        return self.input_values.pad_move or {x = 0, y = 0}
    elseif self.gamepad_mode == "axes" then
        return {
            x = self.input_values.pad_horizontal or 0,
            y = self.input_values.pad_vertical or 0,
        }
    end
    return {
        x = (self.input_values.pad_right or 0) - (self.input_values.pad_left or 0),
        y = (self.input_values.pad_down or 0) - (self.input_values.pad_up or 0),
    }
end

function App:controls_model()
    local scheme = self:active_scheme()
    local source_rows = scheme == "gamepad" and gamepad_rows[self.gamepad_mode] or keyboard_rows
    local rows = {}
    for _, row in ipairs(source_rows) do
        rows[#rows + 1] = {
            action = row.action,
            label = row.label,
            binding = self:prompt(row.action, scheme),
            scheme = scheme,
        }
    end

    local capture = self.controls:capturing()
    local capture_text
    if capture then
        capture_text = "LISTENING · Press the new " .. capture.scheme:upper() .. " input for “"
            .. capture.action:gsub("_", " "):upper() .. "”"
    end

    return {
        scheme = scheme,
        device_label = scheme == "gamepad" and "GAMEPAD" or "KEYBOARD + MOUSE",
        gamepad_mode = self.gamepad_mode,
        rows = rows,
        capture = capture_text,
        footer_hint = scheme == "gamepad"
            and "START resumes · Left stick / D-pad navigates · A selects"
            or "ESC resumes · Arrow keys navigate · Enter selects",
    }
end

function App:hud_model()
    local status = self.game:status()
    local scheme = self:active_scheme()
    status.pause_hint = scheme == "gamepad" and "START · CONTROLS" or "ESC · CONTROLS"
    status.device_label = scheme == "gamepad"
        and ("GAMEPAD · " .. self.gamepad_mode:upper()) or "KEYBOARD · WASD"
    status.dash_hint = self:prompt("dash", scheme) .. " · DASH"
    status.dash_color = status.dash_ready and "accent" or "muted"
    return status
end

return App
