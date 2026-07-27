# ui2d

`ui2d` is a declarative, resolution-independent UI library for LÖVE 11.x. Views describe intent; the runtime owns measurement, layout, font and media caching, pointer/keyboard/controller state, and rendering.

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

Pass `viewport = function() return width, height end` to `UI.new` when the UI
must lay itself out inside a configured game viewport rather than the physical
LÖVE drawable.

## Scoped styles

The stylesheet passed to `UI.new` is the application theme. Views can own partial overrides without repeating that theme:

```lua
local PauseView = UI.view("pause", {
    styles = {
        colors = {accent = {0.92, 0.24, 0.30, 1}},
        buttons = {primary = {background = "accent", radius = 10}},
    },
    build = function(model)
        return UI.screen {
            UI.button {id = "resume", style = "primary", label = "Resume", action = "resume"},
        }
    end,
})
```

A mounted View Layer may override that view again. This is useful when the same view needs a different skin in one context:

```lua
ui:push(PauseView, {
    styles = {
        colors = {accent = {0.26, 0.78, 1, 1}},
    },
})
```

Any node can introduce a style scope for itself and its descendants:

```lua
UI.panel {
    styles = {
        colors = {accent = {0.72, 0.32, 0.96, 1}},
    },
    UI.button {id = "special", style = "primary", label = "Special action"},
}
```

Style resolution proceeds from UI2D defaults to the application theme, view styles, mounted-layer styles, ancestor scopes, the selected named style, direct node properties, and finally interaction state. Every table is a partial deep override, so changing `colors.accent` preserves unrelated typography, spacing, and control styles. Tokens resolve against the nearest scope. View and node scopes do not change the context-wide viewport scale, keeping layered views in one coordinate system.

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

`UI.flow` lays children left-to-right and wraps them onto new lines. Bounded
containers use `overflow = "auto"` by default. They remain visually open while
their content fits; actual excess content activates clipping, wheel scrolling,
draggable horizontal or vertical scrollbars, and controller Selection
visibility. Configure those behaviors independently:

```lua
UI.column {
    id = "inventory",
    width = 360,
    max_height = 420,
    pointer = "block", -- consume otherwise-unhandled pointer input
    overflow_margin = 8, -- let hover transforms escape the clip slightly
    scroll = {
        wheel = true,       -- false disables wheel input
        drag = true,        -- false disables scrollbar dragging
        scrollbar = "auto" -- "hidden" hides it
    },
    children = inventory_rows,
}
```

Use `overflow = "visible"` to opt out or `"hidden"` to clip without scrolling.
`overflow_margin` expands only the visual/hit clip; the scroll viewport and
scrollbar range retain the declared container size. This is useful when a
selected button grows or lifts without allowing offscreen list entries to leak
into the view. Scrollable containers with IDs block otherwise-unhandled pointer
input by default; set `pointer = "pass"` when propagation is intentional.

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

## Fonts, images, sprites, and SVG icons

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

Register raster images or sprite sheets in `images`. Media uses `fit =
"contain"` by default: it preserves aspect ratio and shrinks to fit the space
the layout can actually provide. Use `"cover"` to fill and clip, `"stretch"`
to ignore aspect ratio, or `"none"` only when intrinsic size is intentional.

```lua
local ui = UI.new {
    images = {
        portrait = "assets/portrait.png",
        player = {
            path = "assets/player.png",
            frame_width = 32,
            frame_height = 32,
            filter = "nearest",
        },
    },
}

UI.image {name = "portrait", width = 160, height = 90}
UI.image {name = "player", frame = model.frame, width = 64, height = 64}
```

`quad = {x, y, w, h}` can select an arbitrary raster region. `UI.icon` remains
the semantic constructor for iconography and shares the same media pipeline.

SVG files may be registered in either `images` or the compatible `icons`
registry. The independent `require("graphics.svg")` module owns parsing,
drawing, backdrops, and parsed-data caching; UI2D consumes it like any other
media source. Its lightweight renderer supports paths (`M/L/H/V/C/S/Q/T/Z`),
lines, circles, fills, strokes, tinting, `data-color` slots, `viewBox`, and
compound even-odd/non-zero fills. It intentionally does not implement the
entire browser SVG standard; pre-flatten transforms and unsupported elements
or arc commands in exported assets. A regular color table passed as `tint`
colors the entire SVG; a map such as `tint = {primary = "accent", default =
"white"}` colors elements by their `data-color` value.

Text wraps using the selected font's measured glyph widths:

```lua
UI.text {
    value = model.description,
    width = "fill",
    wrap = true,
    max_lines = 4,
    overflow = "ellipsis",
}
```

Buttons activate immediately on mouse press-down. Selected buttons likewise activate on the Space/Enter keypress; release only clears their pressed visual state and pointer/keyboard capture.

## Text fields

Text fields keep their editing state inside the UI context while accepting declarative values and actions:

```lua
UI.text_field {
    id = "display-name",
    value = model.display_name,
    placeholder = "Display name",
    changed = "rename_player",
    submit = "confirm_name",
    max_length = 32,
}
```

The `changed` and `submit` actions include the current `value`. Text fields support UTF-8 cursor positions, click-and-drag pointer selection, Shift selection, Ctrl/Cmd+Shift word selection, Ctrl/Cmd+A/C/X/V, Ctrl/Cmd+Backspace/Delete, Home/End, horizontal scrolling, and declarative filtering. Forward `mousemoved`, `mousepressed`, `mousereleased`, `keypressed`, `keyreleased`, and `textinput` through `ui:event`.

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

## Sliders, progress, selects, tooltips, and modals

Sliders work with pointer dragging and semantic left/right or up/down
navigation. Their `changed` action includes `control` and the snapped `value`:

```lua
UI.slider {
    id = "music-volume",
    value = model.volume,
    minimum = 0,
    maximum = 1,
    step = 0.05,
    changed = "set_music_volume",
}

UI.progress {
    id = "boss-health",
    value = model.health,
    maximum = model.max_health,
    background = "health_track",
    fill = "health_fill",
    label = model.health .. " HP",
}
```

One `UI.select` supports both flat `options` and optional labeled `groups`;
there is no separate grouped-select control. Long option lists scroll.

```lua
UI.select {
    id = "resolution",
    value = model.resolution,
    groups = {
        {label = "16:9", options = {
            {value = "1280x720", label = "1280 × 720"},
            {value = "1920x1080", label = "1920 × 1080"},
        }},
        {label = "Ultrawide", options = {
            {value = "3440x1440", label = "3440 × 1440"},
        }},
    },
    changed = "set_resolution",
}
```

`UI.tooltip` anchors to a node ID or rectangle. `placement` accepts `"left"`,
`"right"`, `"top"`, `"bottom"`, or `"auto"`; collision handling tries another
side and shifts inside the viewport. Set `collision = "none"` for strict
placement, or provide `place = function(environment) return {x=..., y=...} end`
for full control.

`UI.modal` builds a blocking screen, centered panel, contained navigation
group, and optional action row. Mount it as a blocking View Layer with
`ui:push`; actions remain ordinary asynchronous UI2D actions rather than
pausing the game loop.

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

The default `input_mode = "automatic"` treats the most recently intentional source as authoritative. Controller or keyboard navigation suspends mouse hover and ignores pointer presses until the mouse actually moves; that movement switches back to pointer mode and refreshes hover at the new position. The first semantic accept press after changing from pointer, keyboard, or gamepad mode claims and presents the retained Selection without activating it; a following press from the same source activates normally. If no navigable element owns the current layer, the handoff is not consumed. `ui:input_mode()` reports `pointer`, `keyboard`, `gamepad`, or another semantic source kind, allowing pointer-anchored UI such as tooltips to fall back to the selected node while the controller is active.

Use `UI.new {input_mode = "simultaneous"}` when an interface intentionally wants retained mouse hover and controller Selection to remain active together. `initial_input_mode` may override the default initial `pointer` mode.

Rows and columns infer horizontal and vertical Navigation Groups; flows infer
horizontal groups. Movement within a list follows its children; movement
between compatible sibling lists preserves the selected ordinal. Disabled
controls and nodes with `navigation = false`, `selectable = false`, or
`focusable = false` are skipped. The latter is the clearest declaration for
interactive-looking elements that must never receive Selection. Non-interactive
text, image, and layout nodes are never navigation targets. Analog navigation
applies a dead zone, dominant-axis selection, initial repeat delay, and repeat
interval.

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

When structural grouping cannot decide a move, UI2D scores candidates in the
requested half-plane. Configure `cross_axis_weight` globally, per layer, or on
the view root; a custom `score(environment)` can replace the calculation.
Nodes may provide `navigation_rect` when their useful navigation geometry
differs from their layout rectangle. `UI.Navigation.resolve_rectangles` exposes
the same scoring for headless or game-owned target lists.

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

The UI in Motion example exercises full-screen blocking, a partial pass-through drawer that can tween the same panel to full-screen, a tooltip Hit Blocker, shadered perk-card surfaces, flex layout, hover transitions, and reversible View Layer transitions. Its component lab additionally demonstrates fit-first sprite frames, wrapping text and flow, sliders, animated progress, grouped Select, bounded scrolling, anchored tooltip placement, and a modal:

```powershell
& "C:\Program Files\LOVE\lovec.exe" --console examples\ui2d_layers
```

Set `UI2D_DEMO_PERKS=1` before launching to open the example directly with the single drawer fully raised.

The example also forwards a small handwritten controller adapter directly into `ui:input`: D-pad or left stick navigates, the standardized lower face button accepts, and B invokes the same contextual close actions as the drawer and menu buttons. It intentionally does not require the independent `input` bindings module.

## Internal structure

The public interface remains `require("ui2d")`. Internally, `core/` owns layout, rendering, input routing, View Layers, navigation, motion, resources, units, and style resolution. `components/` contains one behavior-rich control per file: button, text field, segmented control, slider, progress, select, tooltip, and modal. Structural declarations such as screen, row, column, flow, panel, text, icon, image, and spacer remain together in `core/nodes.lua` because they are lightweight node constructors rather than independent controls.
