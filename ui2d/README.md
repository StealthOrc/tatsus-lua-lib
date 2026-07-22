# ui2d

`ui2d` is a declarative, resolution-independent UI library for LÖVE 11.x. Views describe intent; the runtime owns measurement, layout, font and SVG caching, pointer/keyboard state, and rendering.

## Units

Bare numbers are logical UI units. They are multiplied by the stylesheet's viewport scale before rendering. Relative units are explicit:

```lua
width = UI.percent(0.5) -- half of the parent's inner width (0.0 through 1.0)
gap = UI.em(0.5)       -- half of the enclosing text size, or the root size as fallback
width = UI.rem(20)      -- twenty root-font units
x = UI.px(320)          -- exact screen pixels, useful with pointer/rect geometry
```

`"fill"` consumes available space and `"content"` uses measured content. These measurements belong to the stylesheet rather than a theme: a stylesheet may contain structural spacing, typography, shape, and color tokens.

## Minimal view

```lua
local UI = require("ui2d")

local styles = UI.StyleSheet {
    colors = {
        screen = {0.03, 0.035, 0.04, 1},
        fire = {0.92, 0.19, 0.21, 1},
        on_fire = {1, 0.96, 0.90, 1},
    },
    space = {screen = 24, sm = 10},
    radii = {md = 8},
    text = {
        action = {font = "default", weight = "bold", size = 20, color = "on_fire"},
    },
    buttons = {
        primary = {
            background = "fire",
            foreground = "on_fire",
            min_width = 160,
            min_height = 52,
            padding_x = 18,
            padding_y = 12,
            gap = "space.sm",
            radius = "radii.md",
            text = "action",
        },
    },
}

local view = UI.view("fire", function(model)
    return UI.screen {
        background = "screen",
        padding = "space.screen",
        UI.button {
            id = "fire",
            anchor = "bottom-center",
            style = "primary",
            icon = "fire",
            label = "Fire!",
            enabled = model.can_fire,
            action = {type = "fire"},
        },
    }
end)

local ui = UI.new {
    styles = styles,
    icons = {fire = "assets/fire.svg"},
    dispatch = function(action)
        if action.type == "fire" then fire() end
    end,
}

ui:show(view, {model = function() return {can_fire = true} end})
```

Forward LÖVE callbacks with `ui:event(name, ...)`, call `ui:update(dt)` before `ui:draw()`, and use the boolean event result when UI consumption should prevent game input.

The runtime order is: input callbacks queue semantic actions, `ui:update(dt)` dispatches those actions and rebuilds the declarative view from the latest model, then `ui:draw()` renders the resulting layout. Omit `dispatch` and call `ui:take_actions()` when the game prefers to drain the queue itself.

## View Layers and input routing

`show` replaces the Layer Stack with one base View Layer. `push` adds another; `remove` removes a layer by key, and `pop` removes the topmost layer. Layers render from back to front and route input through the exact reverse order.

```lua
ui:show(HudView, {
    key = "hud",
    layer = "base",
    pointer = "pass",
    keyboard = "pass",
})

ui:push(MenuView, {
    key = "menu",
    layer = "overlay",
})

ui:push(DrawerView, {
    key = "drawer",
    layer = "popover",
    pointer = "pass",
})
```

View Layers block pointer and keyboard input by default. A pass-through layer continues routing when no interactive node or panel occupies the pointer position; use `keyboard = "pass"` independently when game input should remain available. Buttons and text fields always consume pointer input; `UI.panel` creates a blocking Hit Region by default, and `pointer = "pass"` makes a panel decorative. The built-in layer names are `base`, `overlay`, `popover`, and `tooltip`; configure or override them with `UI.new {layers = {...}}`.

Node IDs need only be unique within a View Layer. Actions include both `source` and `view`. Buttons may emit `hover_enter` and `hover_leave` actions, which can mount and remove tooltip layers.

For adaptive tooltip placement, `ui:pointer()` returns the current pointer coordinates, `ui:viewport()` returns the drawable size, and `ui:rect(id, view_key)` returns a node's transformed screen-space bounds. Wrap those screen coordinates in `UI.px(...)` when feeding them back into a node transform. This supports fixed viewport anchors, pointer-following tooltips, and target-relative placement that chooses above or below based on available space. A pointer-following panel can explicitly use `pointer = "pass"` to avoid interrupting its own hover source, while fixed or target-relative tooltip panels remain ordinary input blockers.

## Flex layout and Local Z-order

Rows and columns distribute remaining main-axis space using `flex` weights. `flex_basis`, `min_width`, `max_width`, `min_height`, and `max_height` constrain distribution.

```lua
UI.row {
    width = "fill",
    gap = 12,
    UI.panel {flex = 1},
    UI.panel {flex = 2},
}
```

`UI.stack`, `UI.screen`, and `UI.panel` overlap their children. Declaration order is back-to-front; an optional numeric `z` changes Local Z-order. Painting and hit routing always share that order.

## Motion and transitions

Visual transforms are applied after layout and do not move siblings. Translation uses logical or relative UI units; scale and rotation are unitless and radians respectively. The same composed transform is used for rendering and Hit Regions.

```lua
UI.button {
    id = "inventory",
    transform = {translate_y = model.open and 0 or 24},
    opacity = model.open and 1 or 0,
    transition = {
        transform = {duration = 0.25, ease = "out_cubic"},
        opacity = {duration = 0.18, ease = "out_quad"},
    },
}
```

A transitioning node requires an `id`; its Motion Values survive declarative rebuilds and retarget from their current values. Button and text-field styles may define animated interaction states:

```lua
buttons = {
    primary = {
        transform = {translate_y = 0, scale = 1},
        states = {
            hovered = {transform = {translate_y = -4, scale = 1.03}},
            pressed = {transform = {translate_y = 0, scale = 0.97}},
        },
        transition = {
            transform = {duration = 0.14, ease = "out_cubic"},
        },
    },
}
```

View Layers use the same animator for interruptible enter and exit transitions. `remove` retains an exiting layer until it reaches its `from` state; pushing the same key during exit reverses it from its current position.

```lua
ui:push(DrawerView, {
    key = "drawer",
    layer = "popover",
    pointer = "pass",
    transition = {
        from = {opacity = 0, transform = {translate_y = UI.percent(1)}},
        to = {opacity = 1, transform = {translate_y = 0}},
        duration = 0.3,
        ease = "out_cubic",
    },
})
```

Captured buttons can also act as drag handles. Drag lifecycle actions include `x`, `y`, per-event `dx`/`dy`, and press-relative `total_dx`/`total_dy`. Since ordinary button actions fire on press-down, a pure drag handle should omit `action` and decide how to settle from `drag_ended`; near-zero total deltas can be treated as a stationary handle click.

```lua
UI.button {
    id = "drawer-handle",
    label = "Drag drawer",
    semantic_drag = {
        mode = "flick",
        axis = "vertical",
        max_distance = 92,
        flick_threshold = 8,
    },
    drag_started = "drawer_drag_start",
    dragged = "drawer_drag_move",
    drag_ended = "drawer_drag_end",
}
```

Pointer movement drives these actions after mouse capture. A selected drag handle also starts Semantic Drag Capture when accept is held: semantic navigation vectors drive the drag and are consumed instead of changing Selection until accept is released. This behavior is enabled by default for drag handles; set `semantic_drag = false` to disable it. The default `continuous` mode accepts logical-units-per-second `speed`, analog `deadzone`, and an optional `horizontal`/`vertical` `axis` constraint.

`mode = "flick"` turns the stick into a bounded, spring-like pull rather than unlimited travel. `max_distance` caps its preview distance, `response` tunes how quickly it follows the stick, and `flick_threshold` controls gesture recognition. Returning the stick to neutral after a recognized flick ends the drag even while accept remains held; navigation stays captured until accept is released, so the gesture cannot leak into Selection. Semantic drag actions include current pixel velocities as `velocity_x`/`velocity_y`, captured outward stick velocities as `flick_x`/`flick_y`, plus `flicked` and `mode`; a drawer can use the sign of a recognized flick to settle exactly one state in that direction.

Use `dragged` values to directly control a transform while held, then retarget the same Motion Value from `drag_ended` to settle or snap the surface. A stationary press reports zero total distance, so callers can leave the surface unchanged rather than treating a click as a directional gesture.

## Fonts and SVG icons

Font families map weights to LÖVE-readable font files. A text style selects a family, weight, and logical size:

```lua
local styles = UI.StyleSheet {
    fonts = {
        ui = {
            regular = "assets/fonts/Inter-Regular.ttf",
            bold = "assets/fonts/Inter-Bold.ttf",
            filter = "linear",
        },
    },
    text = {
        body = {font = "ui", weight = "regular", size = 16},
        action = {font = "ui", weight = "bold", size = 20},
    },
}

UI.text {value = "Status", style = "body"}
UI.button {id = "fire", label = "Fire!", text_style = "action"}
UI.text_field {id = "name", text_style = "body"}
```

When no file is assigned to a family, LÖVE's default font is used. Configured font files are cached by path and rendered size; an invalid configured path raises an error instead of silently changing the typeface.

SVG files are registered by semantic name in `UI.new {icons = {...}}` and used with either `UI.icon` or a button's `icon` shorthand. The built-in lightweight renderer supports paths (`M/L/H/V/C/S/Q/T/Z`), lines, circles, fills, strokes, tinting, `viewBox`, and compound even-odd/non-zero fills. It intentionally does not implement the entire browser SVG standard; pre-flatten transforms and unsupported elements or arc commands in exported assets.

Buttons activate immediately on mouse press-down. Selected buttons likewise activate on the Space/Enter keypress; release only clears their pressed visual state and pointer/keyboard capture. Text fields support UTF-8 cursor positions, pointer selection, clipboard shortcuts, word deletion, Home/End, and declarative change/submit actions.

A button with `hold` delays its ordinary `action` until it has remained pressed for the requested duration. Pointer holds cancel when the pointer leaves the button by default; early pointer, keyboard, or controller release also cancels and resets progress. The same behavior works through semantic `accept` input:

```lua
UI.button {
    id = "hold-open-drawer",
    label = "Hold to fully open drawer",
    action = "open_drawer_fully",
    hold = {
        duration = 1,
        started = "hold_started",   -- optional
        progress = "hold_progress", -- optional; includes progress, elapsed, duration
        cancelled = "hold_cancelled",
        cancel_on_leave = true,
    },
    hold_indicator = {
        direction = "right", -- right, left, down, or up
        background = "white",
        opacity = 0.3,
    },
}
```

`hold.completed` may provide a completion action instead of the button's normal `action`. `ui:hold_progress(id, view_key)` exposes the live `0`–`1` value, a `holding` interaction style can animate the held state, and shader uniform functions can read `environment.item.hold_progress`. This leaves the built-in fill optional while custom rendering and game behavior can react to the same lifecycle.

## Segmented controls

`UI.segmented_control` is a reusable, controller-navigable choice between two or more mutually exclusive values. Each segment is an ordinary UI2D button, so pointer press-down, semantic selection and accept, disabled state, styles, and navigation all work without a separate input adapter. The indicator animates between values when the view model changes:

```lua
UI.segmented_control {
    id = "movement-shape",
    value = model.movement_shape,
    options = {
        {value = "stick", label = "STICK"},
        {value = "axes", label = "AXES"},
        {value = "directions", label = "DIRECTIONS"},
    },
    changed = "set_movement_shape",
    button_style = "segment",
    selected_style = "segment_active",
    background = "panel_soft",
    indicator_background = "accent_soft",
}
```

The dispatched action includes `control`, `value`, and the one-based `index`. `changed` may also be an action table, and `enabled = false` disables every segment.

## Selection and controller navigation

UI2D keeps mouse-only `hovered`, activation `pressed`, controller/keyboard `selected`, and text-editing `focused` states distinct. A pointer-hovered item also presents as selected while pointer input is active; actual controller or keyboard navigation switches selection back without a stationary cursor stealing it during declarative rebuilds. `hover_enter`, `hover_leave`, `press_started`, `press_ended`, `select_enter`, and `select_leave` actions allow behavior to follow the same lifecycle as the visual states.

When `selected` has no explicit visual state, it falls back to `hovered`. Named state aliases make deliberate sharing explicit while preserving independent overrides:

```lua
states = {
    highlighted = {background = "accent", transform = {scale = 1.04}},
    hovered = "highlighted",
    selected = "highlighted",
    pressed = {transform = {scale = 0.97}},
}
```

UI2D accepts semantic input rather than choosing physical controller buttons:

```lua
ui:input {action = "navigate", value = {x = 0, y = 1}, phase = "changed",
    source = {kind = "gamepad", id = joystick:getID()}}
ui:input {action = "accept", phase = "pressed", source = {kind = "gamepad"}}
ui:input {action = "accept", phase = "released", source = {kind = "gamepad"}}
```

The default `input_mode = "automatic"` treats the most recently intentional source as authoritative. Controller or keyboard navigation suspends mouse hover and ignores pointer presses until the mouse actually moves; that movement switches back to pointer mode and refreshes hover at the new position. `ui:input_mode()` reports `pointer`, `keyboard`, `gamepad`, or another semantic source kind, allowing pointer-anchored UI such as tooltips to fall back to the selected node while the controller is active.

Use `UI.new {input_mode = "simultaneous"}` when an interface intentionally wants retained mouse hover and controller Selection to remain active together. `initial_input_mode` may override the default initial `pointer` mode.

Rows and columns infer horizontal and vertical Navigation Groups. Movement within a list follows its children; movement between compatible sibling lists preserves the selected ordinal. Disabled controls and nodes with `navigation = false` are skipped. Analog navigation applies a dead zone, dominant-axis selection, initial repeat delay, and repeat interval.

Automatic behavior can be adjusted at the context, View Layer, root, container, or node:

```lua
local ui = UI.new {
    navigation = {wrap = false, repeat_delay = 0.35, repeat_interval = 0.10},
}

UI.column {
    navigation = {entry = "resume", wrap = false},
    UI.button {id = "resume", navigate = {right = "settings"}},
    UI.button {id = "decorative", navigation = false},
}
```

A `resolve(request)` function may return a target ID, `false` to stop movement, or `nil` to retain automatic behavior. Set `mode = "manual"` for full control. `ui:select(id, view_key)` selects programmatically and `ui:selected()` returns the active `{id, view, source}`. View Layers block navigation by default; `navigation = "pass"` lets lower layers retain ownership. `keyboard = "pass"` implies navigation pass-through unless the layer explicitly uses `navigation = "block"`, allowing controller selection and raw keyboard routing to remain independent.

## Shader surfaces

Register LÖVE pixel shaders by semantic name, then assign them independently to a node's `background`, `border`, or `content` surface. A `shader` shorthand targets the node's primary surface: content for text and icons, background for panels, buttons, and text fields.

```lua
local fluid = {
    name = "perk_fluid",
    uniforms = {
        seed = 17,
        cursed = 0,
        hex_radius = function(environment)
            local rect = environment.item.visual_rect
            return math.max(2.2, math.min(3.6, math.min(rect.w, rect.h) * 0.0525))
        end,
    },
}

local ui = UI.new {
    shaders = {perk_fluid = "shaders/perk_fluid.glsl"},
}

UI.panel {
    background = "white",
    border = "white",
    shaders = {background = fluid, border = fluid},
    UI.icon {name = "perk", shader = fluid},
    UI.text {value = "Prismatic", shader = fluid},
}
```

`time`, `rect_origin`, `rect_size`, `viewport_size`, and `opacity` are sent automatically when the shader declares matching uniforms. Explicit uniform values can be constants or functions of the drawing environment. A container's `content` shader is inherited by its descendants unless a child overrides it. Shader state is scoped to one surface and restored afterward, so shadered and ordinary UI can be freely composed.

Content shaders should preserve source alpha when drawing fonts or SVGs—for example, by multiplying the result alpha by `Texel(tex, texture_coords).a`.

Run the example from the repository root:

```powershell
& "C:\Program Files\LOVE\lovec.exe" --console examples\ui2d_fire_button
```

The layered, animated example exercises full-screen blocking, a partial pass-through drawer that can tween the same panel to full-screen, a tooltip Hit Blocker, shadered perk-card surfaces, flex layout, hover transitions, and reversible View Layer transitions:

```powershell
& "C:\Program Files\LOVE\lovec.exe" --console examples\ui2d_layers
```

Set `UI2D_DEMO_PERKS=1` before launching to open the example directly with the single drawer fully raised.

The example also forwards a small handwritten controller adapter directly into `ui:input`: D-pad or left stick navigates, and the standardized lower face button accepts. It intentionally does not require the independent `input` bindings module.
