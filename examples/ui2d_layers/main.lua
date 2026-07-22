package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")

local smoke = os.getenv("UI2D_SMOKE") == "1"
local demo_perks = os.getenv("UI2D_DEMO_PERKS") == "1"
local smoke_finished = false
local ui
local drawer_expanded = false

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
            UI.button {id = "open-drawer", style = "motion", label = "Open lower drawer", action = "open_drawer"},
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
    local icon = UI.icon {
        name = "perk_gem",
        size = 52,
        tint = shader and "white" or "parchment_border",
        shader = spec.content_shader,
    }
    local title = UI.text {
        anchor = "center",
        value = spec.title,
        style = shader and "card_title" or "paper_title",
        shader = spec.title_shader,
    }
    if shader then
        icon = UI.panel {
            width = 64,
            height = 64,
            radius = 32,
            background = "world",
            icon,
        }
        title = UI.panel {
            width = 196,
            height = 34,
            radius = 5,
            background = "world",
            title,
        }
    end
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
            gap = 10,
            icon,
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
    local expanded = model.expanded == true
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
            transform = {translate_y = expanded and 0 or UI.percent(0.67)},
            transition = {
                transform = {duration = 0.38, ease = "out_cubic"},
            },
            UI.column {
                anchor = "top-center",
                width = "fill",
                align = "center",
                gap = 12,
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
                        content_shader = fluid(61, false, 0.52),
                        title_shader = fluid(61, false, 0.52),
                        line_one = "The card, border, icon,",
                        line_two = "and title are shaderable.",
                        effect = "+2 all stats",
                    },
                    card {
                        title = "Blood Price",
                        rarity = "CURSED PERK",
                        background = "white",
                        border = "white",
                        shader = cursed,
                        content_shader = fluid(161, true, 0.52),
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

ui = UI.new {
    styles = styles,
    icons = {perk_gem = "perk-gem.svg"},
    shaders = {perk_fluid = "perk_fluid.glsl"},
    dispatch = function(action)
        if action.type == "open_menu" then
            ui:push(Menu, {key = "menu", layer = "overlay", transition = fade})
        elseif action.type == "close_menu" then
            ui:remove("tooltip")
            ui:remove("drawer")
            ui:remove("menu")
            drawer_expanded = false
        elseif action.type == "open_drawer" then
            drawer_expanded = false
            ui:push(Drawer, {
                key = "drawer",
                layer = "popover",
                pointer = "pass",
                transition = slide,
                model = function() return {expanded = drawer_expanded} end,
            })
        elseif action.type == "close_drawer" then
            ui:remove("tooltip")
            ui:remove("drawer")
            drawer_expanded = false
        elseif action.type == "open_perks" then
            ui:remove("tooltip")
            drawer_expanded = true
        elseif action.type == "close_perks" then
            drawer_expanded = false
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
        drawer_expanded = true
        ui:push(Menu, {key = "menu", layer = "overlay"})
        ui:push(Drawer, {
            key = "drawer",
            layer = "popover",
            pointer = "pass",
            model = function() return {expanded = drawer_expanded} end,
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
