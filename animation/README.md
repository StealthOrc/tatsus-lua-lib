# animation

`animation` provides target-driven, interruptible Motion Values for any LÖVE code. It does not mutate game objects and has no dependency on `ui2d`.

```lua
local Animation = require("animation")

local animator = Animation.new()
local position = animator:value({x = 0, y = 0})

position:to({x = 320, y = 180}, {
    duration = 1,
    ease = "out_cubic",
})

function love.update(dt)
    animator:update(dt)
end

function love.draw()
    local current = position:get()
    love.graphics.circle("fill", current.x, current.y, 12)
end
```

Calling `to` while motion is active starts from the current value. A direct reversal shortens its remaining duration proportionally, so it preserves speed rather than jumping or restarting. Repeating the current target is a no-op.

Motion Values support numbers and fixed-shape nested numeric tables. Included easing names are `linear`, `in_quad`, `out_quad`, `in_out_quad`, `in_cubic`, `out_cubic`, and `in_out_cubic`; an easing function may also be supplied directly.

Use `set(value)` for an intentional immediate jump, `get()` for an isolated copy of the current value, and `is_settled()` to observe completion. The caller owns the clock by passing `dt` to `animator:update(dt)`.
