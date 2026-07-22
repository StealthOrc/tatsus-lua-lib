package.path = "./?.lua;./?/init.lua;" .. package.path

local App = require("app")
local app

-- LÖVE lifecycle -------------------------------------------------------------

function love.load()
    app = App.new()
    app:load()
end

function love.update(dt)
    app:update(dt)
end

function love.draw()
    app:draw()
end

-- Pointer, keyboard, and gamepad callbacks ----------------------------------

function love.mousemoved(...)
    app:mousemoved(...)
end

function love.mousepressed(...)
    app:mousepressed(...)
end

function love.mousereleased(...)
    app:event("mousereleased", ...)
end

function love.wheelmoved(...)
    app:event("wheelmoved", ...)
end

function love.keypressed(...)
    app:input_event("keypressed", ...)
end

function love.keyreleased(...)
    app:input_event("keyreleased", ...)
end

function love.gamepadpressed(...)
    app:input_event("gamepadpressed", ...)
end

function love.gamepadreleased(...)
    app:input_event("gamepadreleased", ...)
end

function love.gamepadaxis(...)
    app:input_event("gamepadaxis", ...)
end

function love.joystickremoved(...)
    app:input_event("joystickremoved", ...)
end

function love.focus(...)
    app:event("focus", ...)
end

function love.resize(width, height)
    app:resize(width, height)
end
