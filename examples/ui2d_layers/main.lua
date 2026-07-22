package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")

local smoke = os.getenv("UI2D_SMOKE") == "1"
local smoke_finished = false
local ui

local styles = UI.StyleSheet {
    viewport = {reference_width = 960, reference_height = 640, min_scale = 0.75, max_scale = 2},
    colors = {
        world = {0.025, 0.04, 0.065, 1},
        overlay = {0.035, 0.045, 0.075, 0.97},
        panel = {0.09, 0.11, 0.17, 1},
        tooltip = {0.13, 0.15, 0.22, 1},
        accent = {0.95, 0.31, 0.23, 1},
        white = {0.96, 0.97, 1, 1},
    },
    text = {
        title = {font = "default", size = 28, color = "white"},
        body = {font = "default", size = 17, color = "white"},
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

local Drawer = UI.view("drawer", function()
    return UI.screen {
        UI.panel {
            id = "drawer-panel",
            anchor = "bottom-center",
            width = "fill",
            height = UI.percent(0.33),
            background = "panel",
            UI.column {
                anchor = "center",
                align = "center",
                gap = 12,
                UI.text {value = "This panel alone blocks the lower third.", style = "body"},
                UI.button {
                    id = "tooltip-term",
                    style = "motion",
                    label = "Hover for tooltip",
                    hover_enter = "show_tooltip",
                    hover_leave = "hide_tooltip",
                },
                UI.button {id = "close-drawer", style = "motion", label = "Close drawer", action = "close_drawer"},
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
    dispatch = function(action)
        if action.type == "open_menu" then
            ui:push(Menu, {key = "menu", layer = "overlay", transition = fade})
        elseif action.type == "close_menu" then
            ui:remove("tooltip")
            ui:remove("drawer")
            ui:remove("menu")
        elseif action.type == "open_drawer" then
            ui:push(Drawer, {key = "drawer", layer = "popover", pointer = "pass", transition = slide})
        elseif action.type == "close_drawer" then
            ui:remove("tooltip")
            ui:remove("drawer")
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
