local Game = {}
Game.__index = Game

local pigments = {
    cyan = {name = "CYAN", color = {0.12, 0.92, 1.00, 1}},
    magenta = {name = "MAGENTA", color = {1.00, 0.18, 0.66, 1}},
    yellow = {name = "YELLOW", color = {1.00, 0.86, 0.16, 1}},
    lime = {name = "LIME", color = {0.46, 1.00, 0.24, 1}},
}

local well_specs = {
    {id = "cyan", x = 0.16, y = 0.25},
    {id = "magenta", x = 0.84, y = 0.25},
    {id = "yellow", x = 0.16, y = 0.76},
    {id = "lime", x = 0.84, y = 0.76},
}

local recipes = {
    {"cyan", "magenta"},
    {"yellow", "lime", "cyan"},
    {"magenta", "yellow", "lime", "cyan"},
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function circle_hits_rect(cx, cy, radius, x, y, width, height)
    local nearest_x = clamp(cx, x, x + width)
    local nearest_y = clamp(cy, y, y + height)
    return (cx - nearest_x) ^ 2 + (cy - nearest_y) ^ 2 <= radius ^ 2
end

local function magnitude(x, y)
    local length = math.sqrt(x * x + y * y)
    if length > 1 then return x / length, y / length, 1 end
    return x, y, length
end

local function direction(x, y)
    local length = math.sqrt(x * x + y * y)
    if length <= 0.0001 then return 0, 0, 0 end
    return x / length, y / length, length
end

local function set_color(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
end

function Game.new()
    return setmetatable({
        player = {x = 0, y = 0, radius = 13, speed = 245, facing_x = 0, facing_y = -1},
        recipe_index = 1,
        delivered = 0,
        carried = nil,
        pickup_pulse = 0,
        ritual_pulse = 0,
        reject_pulse = 0,
        success_timer = 0,
        completed_count = 0,
        trail = {},
        dash_state = nil,
        dash_land = 0,
        dash_burst = 0,
        dash_echoes = {},
    }, Game)
end

function Game:reset(width, height)
    self.width, self.height = width, height
    self.player.x, self.player.y = width * 0.5, height * 0.84
    self.recipe_index, self.delivered, self.carried = 1, 0, nil
    self.pickup_pulse, self.ritual_pulse, self.reject_pulse = 0, 0, 0
    self.success_timer, self.completed_count, self.trail = 0, 0, {}
    self.player.facing_x, self.player.facing_y = 0, -1
    self.dash_state, self.dash_land, self.dash_burst = nil, 0, 0
    self.dash_echoes = {}
end

function Game:resize(width, height)
    if not self.width then return self:reset(width, height) end
    self.player.x = self.player.x / math.max(1, self.width) * width
    self.player.y = self.player.y / math.max(1, self.height) * height
    self.width, self.height = width, height
end

function Game:well_rect(spec)
    local size = math.min(self.width, self.height) * 0.075
    return spec.x * self.width - size / 2, spec.y * self.height - size / 2, size
end

function Game:ritual_rect()
    local size = math.min(self.width, self.height) * 0.225
    return self.width / 2 - size / 2, self.height / 2 - size / 2, size
end

function Game:advance_recipe()
    self.completed_count = self.completed_count + 1
    self.recipe_index = self.recipe_index % #recipes + 1
    self.delivered = 0
    self.success_timer = 0
end

function Game:dash(movement)
    if self.dash_state then return false end
    local dx, dy, amount = direction(movement.x or 0, movement.y or 0)
    if amount < 0.12 then
        dx, dy = self.player.facing_x, self.player.facing_y
    end
    self.player.facing_x, self.player.facing_y = dx, dy
    self.dash_state = {
        x = dx,
        y = dy,
        elapsed = 0,
        windup = 0.055,
        travel = 0.165,
        distance = math.min(self.width, self.height) * 0.22,
        moved = 0,
        echo_elapsed = 0,
    }
    self.dash_land = 0
    return true
end

function Game:update(dt, movement)
    self.pickup_pulse = math.max(0, self.pickup_pulse - dt * 2.8)
    self.ritual_pulse = math.max(0, self.ritual_pulse - dt * 2.4)
    self.reject_pulse = math.max(0, self.reject_pulse - dt * 3.5)
    self.dash_land = math.max(0, self.dash_land - dt)
    self.dash_burst = math.max(0, self.dash_burst - dt * 4.8)
    for index = #self.dash_echoes, 1, -1 do
        local echo = self.dash_echoes[index]
        echo.life = echo.life - dt
        if echo.life <= 0 then table.remove(self.dash_echoes, index) end
    end
    if self.success_timer > 0 then
        self.success_timer = math.max(0, self.success_timer - dt)
        if self.success_timer == 0 then self:advance_recipe() end
    end

    local x, y, amount = magnitude(movement.x or 0, movement.y or 0)
    local player = self.player
    if amount > 0.05 then
        player.facing_x, player.facing_y = direction(x, y)
    end
    local move_x, move_y = x * player.speed * dt, y * player.speed * dt
    if self.dash_state then
        local dash = self.dash_state
        dash.elapsed = dash.elapsed + dt
        if dash.elapsed > dash.windup then
            local progress = clamp((dash.elapsed - dash.windup) / dash.travel, 0, 1)
            local eased = 1 - (1 - progress) ^ 3
            local target = dash.distance * eased
            local travel = math.max(0, target - dash.moved)
            dash.moved = target
            move_x, move_y = dash.x * travel, dash.y * travel
            dash.echo_elapsed = dash.echo_elapsed + dt
            if dash.echo_elapsed >= 0.026 then
                dash.echo_elapsed = dash.echo_elapsed - 0.026
                table.insert(self.dash_echoes, 1, {
                    x = player.x,
                    y = player.y,
                    life = 0.18,
                    duration = 0.18,
                    pigment = self.carried,
                })
            end
        else
            move_x, move_y = 0, 0
        end
        if dash.elapsed >= dash.windup + dash.travel then
            self.dash_state = nil
            self.dash_land = 0.18
            self.dash_burst = 1
        end
    end
    player.x = clamp(player.x + move_x, player.radius + 18, self.width - player.radius - 18)
    player.y = clamp(player.y + move_y, player.radius + 18, self.height - player.radius - 18)

    if amount > 0.05 then
        table.insert(self.trail, 1, {x = player.x, y = player.y, pigment = self.carried})
        while #self.trail > 16 do table.remove(self.trail) end
    end

    for _, well in ipairs(well_specs) do
        local wx, wy, size = self:well_rect(well)
        if circle_hits_rect(player.x, player.y, player.radius, wx, wy, size, size)
            and self.carried ~= well.id
        then
            self.carried = well.id
            self.pickup_pulse = 1
        end
    end

    if not self.carried or self.success_timer > 0 then return end
    local rx, ry, size = self:ritual_rect()
    if not circle_hits_rect(player.x, player.y, player.radius, rx, ry, size, size) then return end

    local recipe = recipes[self.recipe_index]
    if self.carried == recipe[self.delivered + 1] then
        self.delivered = self.delivered + 1
        self.carried = nil
        self.ritual_pulse = 1
        if self.delivered == #recipe then self.success_timer = 1.05 end
    elseif self.reject_pulse == 0 then
        self.reject_pulse = 1
    end
end

function Game:status()
    local carried = self.carried and pigments[self.carried]
    return {
        round = self.recipe_index,
        rounds = #recipes,
        completed = self.completed_count,
        carried = carried and carried.name or "UNTINTED",
        carried_color = carried and carried.color or {0.92, 0.95, 1, 1},
        recipe = recipes[self.recipe_index],
        delivered = self.delivered,
        dash_ready = self.dash_state == nil,
    }
end

local function draw_floor(width, height)
    love.graphics.setColor(0.018, 0.022, 0.033, 1)
    love.graphics.rectangle("fill", 0, 0, width, height)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.16, 0.20, 0.28, 0.16)
    local spacing = math.max(42, math.floor(math.min(width, height) / 12))
    for x = spacing, width, spacing do love.graphics.line(x, 0, x, height) end
    for y = spacing, height, spacing do love.graphics.line(0, y, width, y) end
    love.graphics.setColor(0.45, 0.60, 0.78, 0.08)
    love.graphics.circle("line", width / 2, height / 2, math.min(width, height) * 0.38)
end

function Game:draw_well(spec, time)
    local x, y, size = self:well_rect(spec)
    local pigment = pigments[spec.id]
    local breathe = 0.82 + math.sin(time * 2.2 + spec.x * 7) * 0.12
    love.graphics.setBlendMode("add")
    for layer = 4, 1, -1 do
        local expansion = layer * 8
        set_color(pigment.color, 0.035 * (5 - layer) * breathe)
        love.graphics.rectangle("fill", x - expansion, y - expansion,
            size + expansion * 2, size + expansion * 2, 8, 8)
    end
    love.graphics.setBlendMode("alpha")
    set_color(pigment.color, 0.22)
    love.graphics.rectangle("fill", x, y, size, size, 6, 6)
    set_color(pigment.color, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, size, size, 6, 6)
    love.graphics.line(x + size * 0.3, y + size * 0.5, x + size * 0.7, y + size * 0.5)
    love.graphics.line(x + size * 0.5, y + size * 0.3, x + size * 0.5, y + size * 0.7)
end

function Game:draw_ritual(time)
    local x, y, size = self:ritual_rect()
    local recipe = recipes[self.recipe_index]
    local pulse = self.ritual_pulse > 0 and self.ritual_pulse or 0
    local reject = self.reject_pulse > 0 and self.reject_pulse or 0
    local glow = 0.34 + math.sin(time * 1.8) * 0.06 + pulse * 0.35

    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.36 + reject * 0.4, 0.66 - reject * 0.4, 1, glow * 0.16)
    love.graphics.rectangle("fill", x - 16, y - 16, size + 32, size + 32, 18, 18)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(0.08, 0.11, 0.17, 0.88)
    love.graphics.rectangle("fill", x, y, size, size, 12, 12)
    love.graphics.setColor(0.32 + reject * 0.55, 0.68 - reject * 0.52, 1, 0.82)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, size, size, 12, 12)
    love.graphics.rectangle("line", x + 11, y + 11, size - 22, size - 22, 7, 7)

    local radius = math.max(8, size * 0.065)
    local gap = radius * 2.75
    local start_x = x + size / 2 - gap * (#recipe - 1) / 2
    for index, pigment_id in ipairs(recipe) do
        local pigment = pigments[pigment_id]
        local cx, cy = start_x + (index - 1) * gap, y + size / 2
        if index <= self.delivered then
            set_color(pigment.color, 1)
            love.graphics.circle("fill", cx, cy, radius)
        else
            set_color(pigment.color, 0.28)
            love.graphics.circle("fill", cx, cy, radius)
            set_color(pigment.color, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", cx, cy, radius)
        end
    end

    if self.success_timer > 0 then
        local progress = 1 - self.success_timer / 1.05
        local alpha = math.min(1, progress * 5) * math.min(1, self.success_timer * 4)
        local scale = 0.7 + math.min(1, progress * 4) * 0.3
        local cx, cy = x + size / 2, y + size / 2
        love.graphics.setColor(0.78, 1, 0.90, alpha)
        love.graphics.setLineWidth(8 * scale)
        love.graphics.line(cx - 32 * scale, cy, cx - 9 * scale, cy + 24 * scale,
            cx + 38 * scale, cy - 29 * scale)
    end
end

function Game:draw_player()
    local player = self.player
    local tint = self.carried and pigments[self.carried].color or {0.91, 0.95, 1, 1}
    for index = #self.dash_echoes, 1, -1 do
        local echo = self.dash_echoes[index]
        local fade = echo.life / echo.duration
        local color = echo.pigment and pigments[echo.pigment].color or tint
        set_color(color, fade * 0.18)
        love.graphics.circle("fill", echo.x, echo.y, player.radius * (0.75 + fade * 0.2))
    end
    for index = #self.trail, 1, -1 do
        local point = self.trail[index]
        local alpha = (1 - index / (#self.trail + 1)) * 0.16
        local color = point.pigment and pigments[point.pigment].color or {0.8, 0.9, 1, 1}
        set_color(color, alpha)
        love.graphics.circle("fill", point.x, point.y, player.radius * (0.35 + alpha))
    end

    if self.dash_burst > 0 then
        set_color(tint, self.dash_burst * 0.65)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", player.x, player.y,
            player.radius * (1.15 + (1 - self.dash_burst) * 3.4))
    end
    if self.carried then
        love.graphics.setBlendMode("add")
        set_color(tint, 0.18 + self.pickup_pulse * 0.18)
        love.graphics.circle("fill", player.x, player.y,
            player.radius * (2.1 + self.pickup_pulse * 0.5))
        love.graphics.setBlendMode("alpha")
    end
    local along, across = 1, 1
    if self.dash_state then
        local dash = self.dash_state
        if dash.elapsed < dash.windup then
            local progress = clamp(dash.elapsed / dash.windup, 0, 1)
            along, across = 1 - progress * 0.36, 1 + progress * 0.20
        else
            local progress = clamp((dash.elapsed - dash.windup) / dash.travel, 0, 1)
            along, across = 1.58 - progress * 0.38, 0.66 + progress * 0.24
        end
    elseif self.dash_land > 0 then
        local settle = self.dash_land / 0.18
        along, across = 1 + settle * 0.30, 1 + settle * 0.30
    end

    love.graphics.push()
    love.graphics.translate(player.x, player.y)
    local visual_x = self.dash_state and self.dash_state.x or player.facing_x
    local visual_y = self.dash_state and self.dash_state.y or player.facing_y
    love.graphics.rotate(math.atan(visual_y, visual_x))
    love.graphics.scale(along, across)
    set_color(tint, 1)
    love.graphics.circle("fill", 0, 0, player.radius)
    love.graphics.setColor(1, 1, 1, 0.92)
    love.graphics.circle("fill", -player.radius * 0.28,
        -player.radius * 0.28, player.radius * 0.28)
    love.graphics.pop()
end

function Game:draw()
    if not self.width then return end
    love.graphics.push("all")
    local time = love.timer.getTime()
    local shake = self.dash_state and self.dash_state.elapsed > self.dash_state.windup and 2.1
        or self.dash_burst * 1.4
    if shake > 0 then
        love.graphics.translate(math.sin(time * 93) * shake, math.cos(time * 77) * shake)
    end
    draw_floor(self.width, self.height)
    for _, well in ipairs(well_specs) do self:draw_well(well, time) end
    self:draw_ritual(time)
    self:draw_player()
    love.graphics.pop()
end

return Game
