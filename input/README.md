# input

`input` maps keyboard and standardized LÖVE gamepad controls to semantic Input Actions. It has no dependency on `ui2d`: games may dispatch its actions into UI2D, gameplay, or any other system.

## Binding Sets

Keyboard and controller bindings live in separate Binding Sets, so changing one never overwrites the other. An action declares its value shape and may have any number of alternative bindings:

```lua
local Input = require("input")

local controls = Input.new {
    actions = {
        move = {kind = "axis2d"},
        vertical = {kind = "axis1d"},
        accept = {kind = "button"},
        save = {kind = "button"},
    },
    bindings = {
        keyboard = {
            move = Input.vector2 {up = "w", down = "s", left = "a", right = "d"},
            vertical = Input.digital_axis {negative = "w", positive = "s"},
            accept = {Input.key("return"), Input.key("space")},
            save = Input.chord {"ctrl", "alt", "s"},
        },
        gamepad = {
            move = Input.stick("left"),
            vertical = Input.axis("righty"),
            accept = Input.gamepad_button("a"),
        },
    },
}
```

Available binding shapes are `key`, `gamepad_button`, `chord`, `axis`, `axis_button`, `digital_axis`, `stick`, and `vector2`. Axis bindings accept `deadzone` and `scale`; this allows an action to use either axis of either stick, invert it with `scale = -1`, or treat one axis direction as a digital button.

Forward the raw callbacks that the game wants this module to own:

```lua
function love.keypressed(...) controls:event("keypressed", ...) end
function love.keyreleased(...) controls:event("keyreleased", ...) end
function love.gamepadpressed(...) controls:event("gamepadpressed", ...) end
function love.gamepadreleased(...) controls:event("gamepadreleased", ...) end
function love.gamepadaxis(...) controls:event("gamepadaxis", ...) end
function love.joystickremoved(...) controls:event("joystickremoved", ...) end
```

Configure `dispatch` and call `controls:update(dt)`, or omit it and drain `controls:take_actions()`. Events contain `action`, `phase`, `value`, and a `{kind, id}` source. Button phases are `pressed` and `released`; axes emit `changed`.

## UI2D adapter

UI2D only needs semantic navigation and accept intentions:

```lua
dispatch = function(event)
    if event.action == "ui_navigate" then
        ui:input {action = "navigate", value = event.value,
            phase = event.phase, source = event.source}
    elseif event.action == "ui_accept" then
        ui:input {action = "accept", phase = event.phase, source = event.source}
    end
end
```

This adapter belongs to the game. Neither module imports the other.

## Prompts and rebinding

`prompts(action, scheme)` returns binding descriptors rather than controller-specific artwork. A game can render a keyboard composite as four keys and a stick as one glyph without changing the action model.

```lua
local keyboard_prompts = controls:prompts("move", "keyboard")
local gamepad_prompts = controls:prompts("move", "gamepad")

controls:begin_capture("save", "keyboard")
controls:begin_capture("accept", "gamepad", {append = true})
```

Keyboard capture retains held modifiers as a chord. Gamepad capture records buttons, individual axes, axis directions for button actions, or a complete stick for `axis2d` actions. `set` changes one Binding Set, `active_device` reports the most recently meaningful source, and `export` returns a persistence-ready plain Lua table. Pointer callbacks can explicitly return a shared keyboard-and-pointer interface to that display mode with `controls:set_active_device("keyboard")`; this changes only the active prompt scheme and never rewrites bindings.

The example is a small playable Color Rite game rather than a static control table. WASD and the gamepad bindings move the courier between pigment wells and a central recipe seal; Left Shift or the standardized `rightshoulder` button (RB / R1) triggers its separately rebindable dash. Press Escape or Start to open the centered UI2D controls layer. Its gamepad-only segmented control demonstrates the same movement intention represented as one whole stick, two independent axes, or four independently rebindable directions.

Run the interactive example from the repository root:

```powershell
& "C:\Program Files\LOVE\love.exe" examples\input_bindings
```
