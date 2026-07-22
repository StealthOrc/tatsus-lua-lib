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
    app:event("mousemoved", ...)
end

function love.mousepressed(...)
    app:event("mousepressed", ...)
end

function love.mousereleased(...)
    app:event("mousereleased", ...)
end

function love.wheelmoved(...)
    app:event("wheelmoved", ...)
end

function love.keypressed(...)
    app:event("keypressed", ...)
end

function love.keyreleased(...)
    app:event("keyreleased", ...)
end

function love.textinput(...)
    app:event("textinput", ...)
end

function love.gamepadpressed(...)
    app:gamepadpressed(...)
end

function love.gamepadreleased(...)
    app:gamepadreleased(...)
end

function love.gamepadaxis(...)
    app:gamepadaxis(...)
end

function love.joystickremoved(...)
    app:joystickremoved(...)
end

function love.focus(...)
    app:event("focus", ...)
end

function love.resize(...)
    app:event("resize", ...)
end
