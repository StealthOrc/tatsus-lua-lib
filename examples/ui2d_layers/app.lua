local UI = require("ui2d")
local Styles = require("views.styles")
local HudView = require("views.hud")
local MenuView = require("views.menu")
local DrawerView = require("views.drawer")
local TooltipView = require("views.tooltip")

local App = {}
App.__index = App

local DRAWER_EXPANDED = 0
local DRAWER_LOWERED = 0.67
local DRAWER_CLOSED = 1
local DRAWER_CLOSE_THRESHOLD = 0.84

local tooltip_modes = {"top-right", "pointer", "button"}
local gamepad_directions = {
    dpup = "up",
    dpdown = "down",
    dpleft = "left",
    dpright = "right",
}

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

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function gamepad_source(joystick)
    return {kind = "gamepad", id = joystick:getID()}
end

function App.new()
    local self = setmetatable({
        smoke = os.getenv("UI2D_SMOKE") == "1",
        demo_perks = os.getenv("UI2D_DEMO_PERKS") == "1",
        smoke_finished = false,
        drawer_open = false,
        drawer_progress = DRAWER_LOWERED,
        drawer_dragging = false,
        drawer_drag_origin = DRAWER_LOWERED,
        drawer_settle_duration = 0.38,
        drawer_close_pending = false,
        drawer_close_at = 0,
        tooltip_mode_index = 1,
        tooltip_animate_until = 0,
        gamepad_axes = {},
    }, App)

    self.ui = UI.new {
        styles = Styles,
        shaders = {perk_fluid = "perk_fluid.glsl"},
        dispatch = function(action) self:dispatch(action) end,
    }

    return self
end

function App:load()
    self.ui:show(HudView, {
        key = "hud",
        layer = "base",
        pointer = "pass",
        keyboard = "pass",
        navigation = "block",
    })

    if self.smoke or self.demo_perks then
        self.drawer_open = true
        self.drawer_progress = DRAWER_EXPANDED
        self.ui:push(MenuView, {
            key = "menu",
            layer = "overlay",
            model = function() return self:menu_model() end,
        })
        self.ui:push(DrawerView, {
            key = "drawer",
            layer = "popover",
            pointer = "pass",
            model = function() return self:drawer_model() end,
        })
        if self.smoke then
            self.ui:push(TooltipView, {
                key = "tooltip",
                layer = "tooltip",
                pointer = "pass",
                keyboard = "pass",
                model = function() return self:tooltip_model() end,
            })
        end
    end

    self.ui:update(0)
end

function App:update(dt)
    self.ui:update(dt)
    if self.drawer_close_pending and love.timer.getTime() >= self.drawer_close_at then
        self.drawer_close_pending = false
        self.ui:discard("drawer")
    end
end

function App:draw()
    self.ui:draw()
    if self.smoke and not self.smoke_finished then
        self.smoke_finished = true
        print("ui2d layers example smoke passed")
        love.event.quit(0)
    end
end

function App:event(name, ...)
    self.ui:event(name, ...)
end

function App:gamepadpressed(joystick, button)
    if button == "a" then
        self.ui:input {
            action = "accept",
            phase = "pressed",
            source = gamepad_source(joystick),
        }
    elseif button == "b" then
        self:decline_active_view()
    else
        local direction = gamepad_directions[button]
        if direction then
            self.ui:input {
                action = "navigate",
                direction = direction,
                phase = "pressed",
                source = gamepad_source(joystick),
            }
        end
    end
end

function App:gamepadreleased(joystick, button)
    if button == "a" then
        self.ui:input {
            action = "accept",
            phase = "released",
            source = gamepad_source(joystick),
        }
    else
        local direction = gamepad_directions[button]
        if direction then
            self.ui:input {
                action = "navigate",
                direction = direction,
                phase = "released",
                source = gamepad_source(joystick),
            }
        end
    end
end

function App:gamepadaxis(joystick, axis, value)
    if axis ~= "leftx" and axis ~= "lefty" then return end
    local id = joystick:getID()
    self.gamepad_axes[id] = self.gamepad_axes[id] or {x = 0, y = 0}
    self.gamepad_axes[id][axis == "leftx" and "x" or "y"] = value
    self.ui:input {
        action = "navigate",
        value = self.gamepad_axes[id],
        phase = "changed",
        source = gamepad_source(joystick),
    }
end

function App:joystickremoved(joystick)
    self.gamepad_axes[joystick:getID()] = nil
end

function App:active_tooltip_mode()
    local mode = tooltip_modes[self.tooltip_mode_index]
    if mode == "pointer" and self.ui:input_mode() ~= "pointer" then return "button" end
    return mode
end

function App:menu_model()
    return {drawer_open = self.drawer_open}
end

function App:drawer_model()
    return {
        progress = self.drawer_progress,
        dragging = self.drawer_dragging,
        settle_duration = self.drawer_settle_duration,
        tooltip_mode = tooltip_modes[self.tooltip_mode_index],
        active_tooltip_mode = self:active_tooltip_mode(),
    }
end

function App:tooltip_model()
    local pointer_x, pointer_y = self.ui:pointer()
    local viewport_w, viewport_h = self.ui:viewport()
    return {
        mode = self:active_tooltip_mode(),
        pointer_x = pointer_x,
        pointer_y = pointer_y,
        viewport_w = viewport_w,
        viewport_h = viewport_h,
        target = self.ui:rect("tooltip-term", "drawer"),
        animate_position = love.timer.getTime() < self.tooltip_animate_until and 0.18 or nil,
    }
end

function App:show_drawer()
    self.drawer_open = true
    self.drawer_progress = DRAWER_LOWERED
    self.drawer_dragging = false
    self.drawer_settle_duration = 0.38
    self.drawer_close_pending = false
    self.ui:push(DrawerView, {
        key = "drawer",
        layer = "popover",
        pointer = "pass",
        transition = slide,
        model = function() return self:drawer_model() end,
    })
end

function App:close_drawer()
    self.ui:remove("tooltip")
    self.ui:remove("drawer")
    self.drawer_open = false
    self.drawer_dragging = false
    self.drawer_close_pending = false
end

function App:close_menu()
    self:close_drawer()
    self.ui:remove("menu")
end

function App:decline_active_view()
    if self.drawer_open or self.drawer_close_pending or self.ui:rect("drawer-panel", "drawer") then
        self:close_drawer()
        return true
    end
    if self.ui:rect("close-menu", "menu") then
        self:close_menu()
        return true
    end
    return false
end

function App:dispatch(action)
    if action.type == "open_menu" then
        self.ui:push(MenuView, {
            key = "menu",
            layer = "overlay",
            transition = fade,
            model = function() return self:menu_model() end,
        })
    elseif action.type == "close_menu" then
        self:close_menu()
    elseif action.type == "toggle_drawer" then
        if self.drawer_open then self:close_drawer() else self:show_drawer() end
    elseif action.type == "open_drawer_fully" then
        if not self.drawer_open then self:show_drawer() end
        self.drawer_open = true
        self.drawer_progress = DRAWER_EXPANDED
        self.drawer_dragging = false
        self.drawer_close_pending = false
    elseif action.type == "close_drawer" then
        self:close_drawer()
    elseif action.type == "open_perks" then
        self.ui:remove("tooltip")
        self.drawer_dragging = false
        self.drawer_progress = DRAWER_EXPANDED
    elseif action.type == "close_perks" then
        self.drawer_dragging = false
        self.drawer_progress = DRAWER_LOWERED
    elseif action.type == "drawer_drag_start" then
        self.ui:remove("tooltip")
        self.drawer_drag_origin = self.drawer_progress
        self.drawer_dragging = true
        self.drawer_settle_duration = 0.38
    elseif action.type == "drawer_drag_move" then
        self.drawer_progress = clamp(
            self.drawer_drag_origin + action.total_dy / math.max(1, love.graphics.getHeight()),
            DRAWER_EXPANDED,
            DRAWER_CLOSED
        )
    elseif action.type == "drawer_drag_end" then
        self:finish_drawer_drag(action)
    elseif action.type == "cycle_tooltip_anchor" then
        self.tooltip_mode_index = self.tooltip_mode_index % #tooltip_modes + 1
        self.tooltip_animate_until = love.timer.getTime() + 0.2
    elseif action.type == "show_tooltip" then
        self.ui:push(TooltipView, {
            key = "tooltip",
            layer = "tooltip",
            pointer = "pass",
            keyboard = "pass",
            transition = fade,
            model = function() return self:tooltip_model() end,
        })
    elseif action.type == "hide_tooltip" then
        self.ui:remove("tooltip")
    end
end

function App:finish_drawer_drag(action)
    self.drawer_dragging = false
    if action.cancelled then
        self.drawer_progress = self.drawer_drag_origin
    elseif action.semantic then
        local strength = clamp((math.abs(action.flick_y) - 8) / 32, 0, 1)
        self.drawer_settle_duration = 0.30 - strength * 0.12
        if action.flicked and action.flick_y < 0 then
            self.drawer_progress = DRAWER_EXPANDED
        elseif action.flicked and action.flick_y > 0 then
            if self.drawer_drag_origin < 0.335 then
                self.drawer_progress = DRAWER_LOWERED
            else
                self:schedule_drawer_close(self.drawer_settle_duration)
            end
        else
            self.drawer_progress = self.drawer_drag_origin
        end
    elseif action.total_dy < -3 then
        self.drawer_progress = DRAWER_EXPANDED
    elseif action.total_dy > 3 then
        local should_close = self.drawer_drag_origin >= DRAWER_LOWERED - 0.01
            or self.drawer_progress >= DRAWER_CLOSE_THRESHOLD
        if should_close then
            self:schedule_drawer_close(0.38)
        else
            self.drawer_progress = DRAWER_LOWERED
        end
    else
        self.drawer_progress = self.drawer_drag_origin
    end
end

function App:schedule_drawer_close(duration)
    self.drawer_progress = DRAWER_CLOSED
    self.drawer_open = false
    self.drawer_close_pending = true
    self.drawer_close_at = love.timer.getTime() + duration
end

return App
