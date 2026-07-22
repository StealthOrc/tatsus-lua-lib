package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")

local smoke = os.getenv("UI2D_SMOKE") == "1"
local demo_perks = os.getenv("UI2D_DEMO_PERKS") == "1"
local smoke_finished = false
local ui
local drawer_open = false
local drawer_progress = 0.67
local drawer_dragging = false
local drawer_drag_origin = 0.67

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
                hovered = {transform = {translate_y = -5, scale = 1.03}},
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
        UI.text {value = "Game world / pass-through HUD", style = "body", anchor = "top-left"},
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
    local progress = math.max(0, math.min(0.67, model.progress or 0.67))
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
                transform = {duration = model.dragging and 0 or 0.38, ease = "out_cubic"},
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
                    action = expanded and "close_perks" or "open_perks",
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
                        label = "Hover for tooltip",
                        hover_enter = "show_tooltip",
                        hover_leave = "hide_tooltip",
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

local Tooltip = UI.view("tooltip", function()
    return UI.screen {
        padding = 24,
        UI.panel {
            id = "tooltip-panel",
            anchor = "top-right",
            width = 330,
            padding = 18,
            background = "tooltip",
            UI.column {
                gap = 8,
                UI.text {value = "Tooltip View Layer", style = "title"},
                UI.text {value = "This area blocks input. Everything outside it passes through.", style = "body"},
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
    return {progress = drawer_progress, dragging = drawer_dragging}
end

local function show_drawer()
    drawer_open = true
    drawer_progress = 0.67
    drawer_dragging = false
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
        elseif action.type == "toggle_drawer" then
            if drawer_open then
                ui:remove("tooltip")
                ui:remove("drawer")
                drawer_open = false
                drawer_dragging = false
            else
                show_drawer()
            end
        elseif action.type == "close_drawer" then
            ui:remove("tooltip")
            ui:remove("drawer")
            drawer_open = false
            drawer_dragging = false
        elseif action.type == "open_perks" then
            ui:remove("tooltip")
            drawer_dragging = false
            drawer_progress = 0
        elseif action.type == "close_perks" then
            drawer_dragging = false
            drawer_progress = 0.67
        elseif action.type == "drawer_drag_start" then
            ui:remove("tooltip")
            drawer_drag_origin = drawer_progress
            drawer_dragging = true
        elseif action.type == "drawer_drag_move" then
            drawer_progress = math.max(0, math.min(0.67,
                drawer_drag_origin + action.total_dy / math.max(1, love.graphics.getHeight())))
        elseif action.type == "drawer_drag_end" then
            drawer_dragging = false
            if action.total_dy < -3 then
                drawer_progress = 0
            elseif action.total_dy > 3 then
                drawer_progress = 0.67
            else
                drawer_progress = drawer_progress < 0.335 and 0 or 0.67
            end
        elseif action.type == "show_tooltip" then
            ui:push(Tooltip, {
                key = "tooltip",
                layer = "tooltip",
                pointer = "pass",
                keyboard = "pass",
                transition = fade,
            })
        elseif action.type == "hide_tooltip" then
            ui:remove("tooltip")
        end
    end,
}

function love.load()
    ui:show(Hud, {key = "hud", layer = "base", pointer = "pass", keyboard = "pass"})
    if smoke or demo_perks then
        drawer_open = true
        drawer_progress = 0
        ui:push(Menu, {key = "menu", layer = "overlay"})
        ui:push(Drawer, {
            key = "drawer",
            layer = "popover",
            pointer = "pass",
            model = drawer_model,
        })
    end
    ui:update(0)
end

function love.update(dt) ui:update(dt) end

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
