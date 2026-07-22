package.path = "./?.lua;./?/init.lua;" .. package.path

local function close(actual, expected, message)
    if math.abs(actual - expected) > 0.001 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function run()
    local Animation = require("animation")
    local animator = Animation.new()
    local value = animator:value(0)

    value:to(100, {duration = 1, ease = "linear"})
    animator:update(0.25)

    close(value:get(), 25, "motion value advances toward its target")

    animator = Animation.new()
    value = animator:value(0)
    value:to(100, {duration = 1, ease = "linear"})
    animator:update(0.5)
    value:to(0, {duration = 1, ease = "linear"})
    animator:update(0.5)

    close(value:get(), 0, "direct reversal keeps the original transition speed")

    animator = Animation.new()
    value = animator:value({x = 0, y = 10, color = {0, 0.5, 1, 1}})
    value:to({x = 10, y = 30, color = {1, 1, 0, 0.5}}, {duration = 2, ease = "linear"})
    animator:update(1)
    local current = value:get()

    close(current.x, 5, "table x interpolates")
    close(current.y, 20, "table y interpolates")
    close(current.color[1], 0.5, "nested numeric tables interpolate")
    close(current.color[4], 0.75, "nested alpha interpolates")

    animator = Animation.new()
    value = animator:value(0)
    value:to(1, {duration = 1, ease = "out_cubic"})
    animator:update(0.5)
    close(value:get(), 0.875, "named easing curves are resolved")
end

function love.load()
    local ok, message = xpcall(run, debug.traceback)
    if ok then
        print("animation: 4 tests passed")
        os.exit(0)
    else
        print("animation test failure:\n" .. tostring(message))
        os.exit(1)
    end
end
