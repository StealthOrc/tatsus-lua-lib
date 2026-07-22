local StyleSheet = require("ui2d.core.style_sheet")
local Transform = require("ui2d.core.transform")

local Gestures = {}

function Gestures.point_in_item(item, x, y)
    return item and Transform.contains(item.world_transform, item.rect, x, y)
end

function Gestures.hold_options(node)
    if node.hold == nil or node.hold == false then return nil end
    if type(node.hold) == "number" then return {duration = node.hold} end
    assert(type(node.hold) == "table", "a button hold must be a duration or options table")
    return node.hold
end

function Gestures.draggable(node)
    return node.drag_started ~= nil or node.dragged ~= nil or node.drag_ended ~= nil
end

function Gestures.semantic_drag_options(node)
    if not Gestures.draggable(node) or node.semantic_drag == false then return nil end
    if node.semantic_drag == nil or node.semantic_drag == true then return {} end
    assert(type(node.semantic_drag) == "table",
        "semantic_drag must be false, true, or an options table")
    return node.semantic_drag
end

function Gestures.direction_vector(direction)
    if direction == "left" then return -1, 0 end
    if direction == "right" then return 1, 0 end
    if direction == "up" then return 0, -1 end
    if direction == "down" then return 0, 1 end
    return 0, 0
end

function Gestures.apply_deadzone(value, deadzone)
    local magnitude = math.abs(value or 0)
    if magnitude <= deadzone then return 0 end
    local scaled = (magnitude - deadzone) / math.max(0.001, 1 - deadzone)
    return value < 0 and -scaled or scaled
end

function Gestures.action_value(action, source_id, extra, view_key)
    local result
    if type(action) == "string" then
        result = {type = action}
    elseif type(action) == "table" then
        result = StyleSheet.copy(action)
    else
        return nil
    end
    if result.source == nil then result.source = source_id end
    if result.view == nil then result.view = view_key end
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

function Gestures.drag_values(capture, x, y)
    return {
        x = x,
        y = y,
        dx = x - capture.last_x,
        dy = y - capture.last_y,
        total_dx = x - capture.start_x,
        total_dy = y - capture.start_y,
    }
end

function Gestures.semantic_drag_values(capture, x, y)
    local values = Gestures.drag_values(capture, x, y)
    values.input_source = capture.source
    values.semantic = true
    values.mode = capture.mode
    values.velocity_x = capture.velocity_x
    values.velocity_y = capture.velocity_y
    values.flick_x = capture.flick_x
    values.flick_y = capture.flick_y
    values.flicked = math.max(math.abs(capture.flick_x), math.abs(capture.flick_y))
        >= capture.flick_threshold
    return values
end

function Gestures.outward_velocity(current, previous, elapsed)
    local changed_direction = current * previous < 0
    local moved_outward = math.abs(current) > math.abs(previous) + 0.0001
    if not changed_direction and not moved_outward then return nil end
    return (current - previous) / elapsed
end

function Gestures.retain_flick(current, candidate)
    if not candidate then return current end
    if current == 0 or current * candidate < 0 or math.abs(candidate) > math.abs(current) then
        return candidate
    end
    return current
end

return Gestures
