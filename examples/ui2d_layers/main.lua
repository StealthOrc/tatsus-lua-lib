package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")

local smoke = os.getenv("UI2D_SMOKE") == "1"
local demo_perks = os.getenv("UI2D_DEMO_PERKS") == "1"
local smoke_finished = false
local ui
local DRAWER_EXPANDED, DRAWER_LOWERED, DRAWER_CLOSED = 0, 0.67, 1
local DRAWER_CLOSE_THRESHOLD = 0.84
local drawer_open = false
local drawer_progress = DRAWER_LOWERED
local drawer_dragging = false
local drawer_drag_origin = DRAWER_LOWERED
local drawer_settle_duration = 0.38
local drawer_close_pending = false
local drawer_close_at = 0
local tooltip_modes = {"top-right", "pointer", "button"}
local tooltip_mode_index = 1
local tooltip_animate_until = 0
local gamepad_axes = {}

local function active_tooltip_mode()
    local mode = tooltip_modes[tooltip_mode_index]
    if mode == "pointer" and ui and ui:input_mode() ~= "pointer" then return "button" end
    return mode
end

local styles = UI.StyleSheet {
    viewport = {reference_width = 960, reference_height = 640, min_scale = 0.75, max_scale = 2},
    colors = {
        world = {0.025, 0.04, 0.065, 1},
        overlay = {0.035, 0.045, 0.075, 0.97},
        panel = {0.09, 0.11, 0.17, 1},
        tooltip = {0.13, 0.15, 0.22, 1},
        accent = {0.95, 0.31, 0.23, 1},
        white = {0.96, 0.97, 1, 1},
        ink = {0.12, 0.09, 0.07, 1},
        parchment = {0.94, 0.90, 0.76, 1},
        parchment_border = {0.58, 0.43, 0.24, 1},
        card_light = {1, 0.96, 1, 1},
        card_muted = {0.90, 0.82, 0.91, 1},
    },
    text = {
        title = {font = "default", size = 28, color = "white"},
        body = {font = "default", size = 17, color = "white"},
        card_title = {font = "default", size = 22, color = "card_light"},
        card_body = {font = "default", size = 14, color = "card_muted"},
        paper_title = {font = "default", size = 22, color = "ink"},
        paper_title_inverse = {font = "default", size = 22, color = "parchment"},
        paper_body = {font = "default", size = 14, color = "ink"},
    },
    buttons = {
        motion = {
            background = "accent",
            foreground = "white",
            min_width = 190,
            min_height = 48,
            padding_x = 18,
            padding_y = 10,
            text = "body",
            transform = {translate_y = 0, scale = 1},
            states = {
                highlighted = {transform = {translate_y = -5, scale = 1.03}},
                hovered = "highlighted",
                selected = "highlighted",
                pressed = {transform = {translate_y = 0, scale = 0.97}},
            },
            transition = {
                transform = {duration = 0.16, ease = "out_cubic"},
            },
        },
        drawer_handle = {
            background = "tooltip",
            background_hovered = {0.20, 0.23, 0.32, 1},
            background_pressed = {0.26, 0.29, 0.38, 1},
            foreground = "white",
            min_width = 168,
            min_height = 26,
            padding_x = 18,
            padding_y = 3,
            radius = 13,
            text = "card_body",
        },
    },
}

local Hud = UI.view("hud", function()
    return UI.screen {
        background = "world",
        padding = 28,
        UI.column {
            anchor = "center",
            align = "center",
            gap = 12,
            UI.text {value = "Layers in Motion", style = "title"},
            UI.text {
                value = "Try me with a mouse or gamepad — click below or press accept.",
                style = "body",
            },
        },
        UI.button {
            id = "open-menu",
            anchor = "bottom-center",
            style = "motion",
            label = "Open full menu",
            action = "open_menu",
        },
    }
end)

local Menu = UI.view("menu", function()
    return UI.screen {
        background = "overlay",
        UI.column {
            anchor = "center",
            align = "center",
            gap = 18,
            UI.text {value = "Blocking View Layer", style = "title"},
            UI.text {value = "Nothing behind this view receives input.", style = "body"},
            UI.button {
                id = "toggle-drawer",
                style = "motion",
                label = drawer_open and "Close lower drawer" or "Open lower drawer",
                action = "toggle_drawer",
            },
            UI.button {
                id = "hold-open-drawer",
                style = "motion",
                label = "Hold to fully open drawer",
                action = "open_drawer_fully",
                hold = {duration = 1},
                hold_indicator = {
                    direction = "right",
                    background = "white",
                    opacity = 0.32,
                },
            },
            UI.button {id = "close-menu", style = "motion", label = "Close menu", action = "close_menu"},
        },
    }
end)

local function fluid(seed, cursed, brightness)
    return {
        name = "perk_fluid",
        uniforms = {
            seed = seed,
            cursed = cursed and 1 or 0,
            brightness = brightness or 0,
            hex_radius = 3.2,
        },
    }
end

local function card(spec)
    local shader = spec.shader
    local title = UI.text {
        anchor = "center",
        value = spec.title,
        style = shader and "card_title" or "paper_title_inverse",
        shader = spec.title_shader,
    }
    title = UI.panel {
        width = 196,
        height = 34,
        radius = 5,
        background = shader and "world" or "parchment_border",
        title,
    }
    return UI.panel {
        width = 238,
        height = 292,
        padding = 16,
        radius = 12,
        background = spec.background,
        border = spec.border,
        border_width = 3,
        shaders = shader and {background = shader, border = shader} or nil,
        UI.column {
            anchor = "center",
            align = "center",
            gap = 14,
            title,
            UI.text {value = spec.rarity, style = shader and "card_body" or "paper_body"},
            UI.spacer {height = 4},
            UI.text {value = spec.line_one, style = shader and "card_body" or "paper_body"},
            UI.text {value = spec.line_two, style = shader and "card_body" or "paper_body"},
            UI.spacer {height = 8},
            UI.text {value = spec.effect, style = shader and "card_title" or "paper_title"},
        },
    }
end

local Drawer = UI.view("drawer", function(model)
    local progress = math.max(DRAWER_EXPANDED, math.min(DRAWER_CLOSED,
        model.progress or DRAWER_LOWERED))
    local expanded = progress < 0.335
    local prismatic = fluid(17, false)
    local cursed = fluid(117, true)
    return UI.screen {
        UI.panel {
            id = "drawer-panel",
            anchor = "bottom-center",
            width = "fill",
            height = "fill",
            padding = 24,
            background = "panel",
            border = "accent",
            border_width = 2,
            transform = {translate_y = UI.percent(progress)},
            transition = {
                transform = {
                    duration = model.dragging and 0 or (model.settle_duration or 0.38),
                    ease = "out_cubic",
                },
            },
            UI.column {
                anchor = "top-center",
                width = "fill",
                align = "center",
                gap = 12,
                UI.button {
                    id = "drawer-grab-handle",
                    style = "drawer_handle",
                    label = "=  DRAG DRAWER  =",
                    semantic_drag = {
                        mode = "flick",
                        axis = "vertical",
                        max_distance = 92,
                        response = 20,
                        flick_threshold = 8,
                    },
                    drag_started = "drawer_drag_start",
                    dragged = "drawer_drag_move",
                    drag_ended = "drawer_drag_end",
                },
                UI.text {value = "This panel blocks only the part currently visible.", style = "body"},
                UI.row {
                    width = "fill",
                    justify = "center",
                    gap = 12,
                    UI.button {
                        id = "tooltip-term",
                        style = "motion",
                        label = "Tooltip: " .. tooltip_modes[tooltip_mode_index]
                            .. (tooltip_modes[tooltip_mode_index] == "pointer"
                                and active_tooltip_mode() == "button" and " (selection)" or ""),
                        action = "cycle_tooltip_anchor",
                        hover_enter = "show_tooltip",
                        hover_leave = "hide_tooltip",
                        select_enter = "show_tooltip",
                        select_leave = "hide_tooltip",
                    },
                    UI.button {
                        id = "toggle-perks",
                        style = "motion",
                        label = expanded and "Lower drawer" or "Pull drawer further up",
                        action = expanded and "close_perks" or "open_perks",
                    },
                    UI.button {id = "close-drawer", style = "motion", label = "Close drawer", action = "close_drawer"},
                },
                UI.text {value = "Shader Surfaces / Perk Draft", style = "title"},
                UI.text {value = "These cards always live below the controls in this same view.", style = "body"},
                UI.row {
                    width = "fill",
                    justify = "center",
                    gap = 18,
                    card {
                        title = "Steady Hand",
                        rarity = "NORMAL PERK",
                        background = "parchment",
                        border = "parchment_border",
                        line_one = "Reliable power with",
                        line_two = "no strange conditions.",
                        effect = "+12% precision",
                    },
                    card {
                        title = "Star Bloom",
                        rarity = "PRISMATIC PERK",
                        background = "white",
                        border = "white",
                        shader = prismatic,
                        title_shader = fluid(61, false, 0.52),
                        line_one = "The card, border, and title",
                        line_two = "use separate shader surfaces.",
                        effect = "+2 all stats",
                    },
                    card {
                        title = "Blood Price",
                        rarity = "CURSED PERK",
                        background = "white",
                        border = "white",
                        shader = cursed,
                        title_shader = fluid(161, true, 0.52),
                        line_one = "Great power, paid for",
                        line_two = "whenever you are hit.",
                        effect = "+40% damage",
                    },
                },
            },
        },
    }
end)

local tooltip_width, tooltip_height = 330, 158
local tooltip_margin, tooltip_gap = 24, 12

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function tooltip_position(model)
    local viewport_w = model.viewport_w or 960
    local viewport_h = model.viewport_h or 640
    if model.mode == "pointer" then
        local x = clamp((model.pointer_x or 0) + tooltip_gap,
            tooltip_margin, viewport_w - tooltip_width - tooltip_margin)
        local below = (model.pointer_y or 0) + tooltip_gap
        local y = below + tooltip_height <= viewport_h - tooltip_margin
            and below or (model.pointer_y or 0) - tooltip_height - tooltip_gap
        return x, clamp(y, tooltip_margin, viewport_h - tooltip_height - tooltip_margin), "pointer"
    elseif model.mode == "button" and model.target then
        local target = model.target
        local x = target.x + (target.w - tooltip_width) / 2
        local above = target.y - tooltip_height - tooltip_gap
        local side = above >= tooltip_margin and "above button" or "below button"
        local y = side == "above button" and above or target.y + target.h + tooltip_gap
        return clamp(x, tooltip_margin, viewport_w - tooltip_width - tooltip_margin),
            clamp(y, tooltip_margin, viewport_h - tooltip_height - tooltip_margin), side
    end
    return viewport_w - tooltip_width - tooltip_margin, tooltip_margin, "top-right"
end

local Tooltip = UI.view("tooltip", function(model)
    local x, y, placement = tooltip_position(model)
    return UI.screen {
        UI.panel {
            id = "tooltip-panel",
            anchor = "top-left",
            width = tooltip_width,
            height = tooltip_height,
            padding = 18,
            radius = 8,
            pointer = model.mode == "pointer" and "pass" or nil,
            background = "tooltip",
            border = "accent",
            border_width = 2,
            transform = {translate_x = UI.px(x), translate_y = UI.px(y)},
            transition = {
                transform = {
                    duration = model.animate_position or (model.mode ~= "pointer" and 0.18 or 0),
                    ease = "out_cubic",
                },
            },
            UI.column {
                gap = 8,
                UI.text {value = "Tooltip · " .. placement, style = "title"},
                UI.text {value = "Click to cycle anchor policies.", style = "body"},
                UI.text {
                    value = model.mode == "pointer" and "Pointer-follow mode passes input."
                        or "Inside consumes pointer input.",
                    style = "body",
                },
                UI.text {value = "Outside remains pass-through.", style = "body"},
            },
        },
    }
end)

local fade = {
    from = {opacity = 0, transform = {scale = 0.98}},
    to = {opacity = 1, transform = {scale = 1}},
    duration = 0.2,
    ease = "out_cubic",
}

local slide = {
    from = {opacity = 0, transform = {translate_y = UI.percent(1)}},
    to = {opacity = 1, transform = {translate_y = 0}},
    duration = 0.3,
    ease = "out_cubic",
}

local function drawer_model()
    return {
        progress = drawer_progress,
        dragging = drawer_dragging,
        settle_duration = drawer_settle_duration,
    }
end

local function tooltip_model()
    local pointer_x, pointer_y = ui:pointer()
    local viewport_w, viewport_h = ui:viewport()
    return {
        mode = active_tooltip_mode(),
        pointer_x = pointer_x,
        pointer_y = pointer_y,
        viewport_w = viewport_w,
        viewport_h = viewport_h,
        target = ui:rect("tooltip-term", "drawer"),
        animate_position = love.timer.getTime() < tooltip_animate_until and 0.18 or nil,
    }
end

local function show_drawer()
    drawer_open = true
    drawer_progress = DRAWER_LOWERED
    drawer_dragging = false
    drawer_settle_duration = 0.38
    drawer_close_pending = false
    ui:push(Drawer, {
        key = "drawer",
        layer = "popover",
        pointer = "pass",
        transition = slide,
        model = drawer_model,
    })
end

ui = UI.new {
    styles = styles,
    shaders = {perk_fluid = "perk_fluid.glsl"},
    dispatch = function(action)
        if action.type == "open_menu" then
            ui:push(Menu, {key = "menu", layer = "overlay", transition = fade})
        elseif action.type == "close_menu" then
            ui:remove("tooltip")
            ui:remove("drawer")
            ui:remove("menu")
            drawer_open = false
            drawer_dragging = false
            drawer_close_pending = false
        elseif action.type == "toggle_drawer" then
            if drawer_open then
                ui:remove("tooltip")
                ui:remove("drawer")
                drawer_open = false
                drawer_dragging = false
                drawer_close_pending = false
            else
                show_drawer()
            end
        elseif action.type == "open_drawer_fully" then
            if not drawer_open then show_drawer() end
            drawer_open = true
            drawer_progress = DRAWER_EXPANDED
            drawer_dragging = false
            drawer_close_pending = false
        elseif action.type == "close_drawer" then
            ui:remove("tooltip")
            ui:remove("drawer")
            drawer_open = false
            drawer_dragging = false
            drawer_close_pending = false
        elseif action.type == "open_perks" then
            ui:remove("tooltip")
            drawer_dragging = false
            drawer_progress = DRAWER_EXPANDED
        elseif action.type == "close_perks" then
            drawer_dragging = false
            drawer_progress = DRAWER_LOWERED
        elseif action.type == "drawer_drag_start" then
            ui:remove("tooltip")
            drawer_drag_origin = drawer_progress
            drawer_dragging = true
            drawer_settle_duration = 0.38
        elseif action.type == "drawer_drag_move" then
            drawer_progress = math.max(DRAWER_EXPANDED, math.min(DRAWER_CLOSED,
                drawer_drag_origin + action.total_dy / math.max(1, love.graphics.getHeight())))
        elseif action.type == "drawer_drag_end" then
            drawer_dragging = false
            if action.cancelled then
                drawer_progress = drawer_drag_origin
            elseif action.semantic then
                local strength = clamp((math.abs(action.flick_y) - 8) / 32, 0, 1)
                drawer_settle_duration = 0.30 - strength * 0.12
                if action.flicked and action.flick_y < 0 then
                    drawer_progress = DRAWER_EXPANDED
                elseif action.flicked and action.flick_y > 0 then
                    if drawer_drag_origin < 0.335 then
                        drawer_progress = DRAWER_LOWERED
                    else
                        drawer_progress = DRAWER_CLOSED
                        drawer_open = false
                        drawer_close_pending = true
                        drawer_close_at = love.timer.getTime() + drawer_settle_duration
                    end
                else
                    drawer_progress = drawer_drag_origin
                end
            elseif action.total_dy < -3 then
                drawer_progress = DRAWER_EXPANDED
            elseif action.total_dy > 3 then
                local close = drawer_drag_origin >= DRAWER_LOWERED - 0.01
                    or drawer_progress >= DRAWER_CLOSE_THRESHOLD
                if close then
                    drawer_progress = DRAWER_CLOSED
                    drawer_open = false
                    drawer_close_pending = true
                    drawer_close_at = love.timer.getTime() + 0.38
                else
                    drawer_progress = DRAWER_LOWERED
                end
            else
                drawer_progress = drawer_drag_origin
            end
        elseif action.type == "cycle_tooltip_anchor" then
            tooltip_mode_index = tooltip_mode_index % #tooltip_modes + 1
            tooltip_animate_until = love.timer.getTime() + 0.2
        elseif action.type == "show_tooltip" then
            ui:push(Tooltip, {
                key = "tooltip",
                layer = "tooltip",
                pointer = "pass",
                keyboard = "pass",
                transition = fade,
                model = tooltip_model,
            })
        elseif action.type == "hide_tooltip" then
            ui:remove("tooltip")
        end
    end,
}

function love.load()
    ui:show(Hud, {
        key = "hud",
        layer = "base",
        pointer = "pass",
        keyboard = "pass",
        navigation = "block",
    })
    if smoke or demo_perks then
        drawer_open = true
        drawer_progress = DRAWER_EXPANDED
        ui:push(Menu, {key = "menu", layer = "overlay"})
        ui:push(Drawer, {
            key = "drawer",
            layer = "popover",
            pointer = "pass",
            model = drawer_model,
        })
        if smoke then
            ui:push(Tooltip, {
                key = "tooltip",
                layer = "tooltip",
                pointer = "pass",
                keyboard = "pass",
                model = tooltip_model,
            })
        end
    end
    ui:update(0)
end

function love.update(dt)
    ui:update(dt)
    if drawer_close_pending and love.timer.getTime() >= drawer_close_at then
        drawer_close_pending = false
        ui:discard("drawer")
    end
end

function love.draw()
    ui:draw()
    if smoke and not smoke_finished then
        smoke_finished = true
        print("ui2d layers example smoke passed")
        love.event.quit(0)
    end
end

function love.mousemoved(...) ui:event("mousemoved", ...) end
function love.mousepressed(...) ui:event("mousepressed", ...) end
function love.mousereleased(...) ui:event("mousereleased", ...) end
function love.wheelmoved(...) ui:event("wheelmoved", ...) end
function love.keypressed(...) ui:event("keypressed", ...) end
function love.keyreleased(...) ui:event("keyreleased", ...) end
function love.textinput(...) ui:event("textinput", ...) end
function love.resize(...) ui:event("resize", ...) end

local function gamepad_source(joystick)
    return {kind = "gamepad", id = joystick:getID()}
end

function love.gamepadpressed(joystick, button)
    if button == "a" then
        ui:input {action = "accept", phase = "pressed", source = gamepad_source(joystick)}
    else
        local direction = ({dpup = "up", dpdown = "down", dpleft = "left", dpright = "right"})[button]
        if direction then
            ui:input {action = "navigate", direction = direction, phase = "pressed",
                source = gamepad_source(joystick)}
        end
    end
end

function love.gamepadreleased(joystick, button)
    if button == "a" then
        ui:input {action = "accept", phase = "released", source = gamepad_source(joystick)}
    else
        local direction = ({dpup = "up", dpdown = "down", dpleft = "left", dpright = "right"})[button]
        if direction then
            ui:input {action = "navigate", direction = direction, phase = "released",
                source = gamepad_source(joystick)}
        end
    end
end

function love.gamepadaxis(joystick, axis, value)
    if axis ~= "leftx" and axis ~= "lefty" then return end
    local id = joystick:getID()
    gamepad_axes[id] = gamepad_axes[id] or {x = 0, y = 0}
    gamepad_axes[id][axis == "leftx" and "x" or "y"] = value
    ui:input {action = "navigate", value = gamepad_axes[id], phase = "changed",
        source = gamepad_source(joystick)}
end

function love.joystickremoved(joystick)
    gamepad_axes[joystick:getID()] = nil
end
