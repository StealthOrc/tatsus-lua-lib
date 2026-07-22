# ui2d

`ui2d` is a declarative, resolution-independent UI library for LÖVE 11.x. Views describe intent; the runtime owns measurement, layout, font and SVG caching, pointer/keyboard state, and rendering.

## Units

Bare numbers are logical UI units. They are multiplied by the stylesheet's viewport scale before rendering. Relative units are explicit:

```lua
width = UI.percent(0.5) -- half of the parent's inner width (0.0 through 1.0)
gap = UI.em(0.5)       -- half of the enclosing text size, or the root size as fallback
width = UI.rem(20)      -- twenty root-font units
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

Buttons activate on release over the same captured button and support Tab focus plus Space/Enter activation. Text fields support UTF-8 cursor positions, pointer selection, clipboard shortcuts, word deletion, Home/End, and declarative change/submit actions.

Run the example from the repository root:

```powershell
& "C:\Program Files\LOVE\lovec.exe" --console examples\ui2d_fire_button
```

The layered, animated example exercises full-screen blocking, a partial pass-through drawer, a tooltip Hit Blocker, flex layout, hover transitions, and reversible View Layer transitions:

```powershell
& "C:\Program Files\LOVE\lovec.exe" --console examples\ui2d_layers
```
