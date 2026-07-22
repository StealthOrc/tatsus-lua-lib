package.path = "./?.lua;./?/init.lua;" .. package.path

local UI = require("ui2d")

local fired = 0
local smoke = os.getenv("UI2D_SMOKE") == "1"
local smoke_finished = false

local styles = UI.StyleSheet {
    viewport = {
        reference_width = 1920,
        reference_height = 1080,
        scale_mode = "contain",
        min_scale = 0.5,
        max_scale = 2,
    },
    colors = {
        screen = {0.03, 0.035, 0.04, 1},
        fire = {0.92, 0.19, 0.21, 1},
        on_fire = {1, 0.96, 0.90, 1},
    },
    fonts = {
        -- Add `regular` and `bold` paths here to use a bundled font family.
        ui = {},
    },
    text = {
        action = {font = "ui", weight = "bold", size = 20, color = "on_fire"},
    },
    space = {screen = 24, sm = 10},
    radii = {md = 8},
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

local FireView = UI.view("fire", function()
    return UI.screen {
        background = "screen",
        padding = "space.screen",
        UI.button {
            id = "fire",
            anchor = "bottom-center",
            style = "primary",
            icon = "fire",
            label = "Fire!",
            action = {type = "fire"},
        },
    }
end)

local ui = UI.new {
    styles = styles,
    icons = {fire = "fire.svg"},
    dispatch = function(action)
        if action.type == "fire" then fired = fired + 1 end
    end,
}

function love.load()
    ui:show(FireView)
    ui:update(0)
end

function love.update(dt)
    ui:update(dt)
end

function love.draw()
    ui:draw()
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.print("Fired: " .. tostring(fired), 16, 16)
    if smoke and not smoke_finished then
        smoke_finished = true
        print("ui2d example smoke passed")
        love.event.quit(0)
    end
end

function love.mousemoved(...)
    ui:event("mousemoved", ...)
end

function love.mousepressed(...)
    ui:event("mousepressed", ...)
end

function love.mousereleased(...)
    ui:event("mousereleased", ...)
end

function love.keypressed(...)
    ui:event("keypressed", ...)
end

function love.keyreleased(...)
    ui:event("keyreleased", ...)
end

function love.textinput(...)
    ui:event("textinput", ...)
end

function love.resize(...)
    ui:event("resize", ...)
end
