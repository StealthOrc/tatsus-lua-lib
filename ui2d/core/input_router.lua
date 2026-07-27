local TextField = require("ui2d.components.text_field")
local Gestures = require("ui2d.core.gestures")
local Navigation = require("ui2d.core.navigation")

local InputRouter = {}

function InputRouter.input(context, event)
    assert(type(event) == "table", "ui2d input expects an event table")
    local action = event.action or event.name or event.type
    local source = event.source or "navigation"
    if action == "accept" then
        if event.phase == "released" then return context:release_selection(source) end
        if event.phase == nil or event.phase == "pressed" then
            return context:accept_selection(source)
        end
        return false
    elseif action ~= "navigate" then
        return false
    end

    local value = event.value or event
    local x, y = value.x or 0, value.y or 0
    if context.semantic_drag then return context:set_semantic_drag_input(event, source) end
    if context.keyboard_pressed and context.keyboard_pressed.semantic_drag then
        context.navigation_input = {x = x, y = y}
        return true
    end
    local options = context:navigation_options_for(context:navigation_owner())
    local direction = event.direction or Navigation.direction(x, y,
        event.threshold or options.threshold or 0.5)
    if event.phase == "released" then direction = nil end
    if context.navigation_input.drag_latched then
        context.navigation_input = {x = x, y = y, drag_latched = direction ~= nil}
        return true
    end
    if event.phase == "pressed" and event.direction then
        return context:navigate(event.direction, source)
    end
    if event.phase == "released" or not direction then
        context.navigation_input = {x = x, y = y}
        return false
    end
    local held = context.navigation_input
    local changed = held.direction ~= direction
    context.navigation_input = {
        x = x,
        y = y,
        direction = direction,
        source = source,
        repeat_at = changed and (context.time + (options.repeat_delay or 0.35))
            or held.repeat_at,
    }
    if changed then return context:navigate(direction, source) end
    return true
end

function InputRouter.event(context, name, ...)
    if #context.layers.entries > 0 and not context.layers.entries[1].layout then
        context:rebuild()
    end
    local args = {...}
    if name == "resize" then
        context:rebuild()
        return #context.layers.entries > 0
    elseif name == "focus" and args[1] == false then
        context:cancel_hold("focus_lost")
        context:end_semantic_drag("focus_lost")
        context.pressed, context.pointer_capture, context.keyboard_pressed = nil, nil, nil
        context.cancelled_pointer_button = nil
        return false
    elseif name == "mousemoved" then
        context.pointer_x, context.pointer_y = args[1], args[2]
        context:use_pointer_selection()
        local capture = context.pointer_capture
        if capture and capture.kind == "scrollbar" then
            local entry = context.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            if item then
                context:set_scrollbar_pointer(
                    item,
                    context.pointer_y,
                    capture.scrollbar_offset
                )
            end
            return true
        end
        if capture then
            local entry = context.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            local options = item and Gestures.hold_options(item.node)
            if options and options.cancel_on_leave ~= false
                and not Gestures.point_in_item(item, context.pointer_x, context.pointer_y)
            then
                context:cancel_hold("pointer_left")
                context.pressed = nil
            end
            if item and capture.draggable then
                local values = Gestures.drag_values(capture, context.pointer_x, context.pointer_y)
                context:queue(item.node.dragged, item.node.id, values, entry.key)
            end
            if item and item.kind == "slider" then
                context:change_slider(
                    entry,
                    item,
                    context.pointer_x,
                    context.pointer_y,
                    "pointer"
                )
            end
            capture.last_x, capture.last_y = context.pointer_x, context.pointer_y
        end
        if capture and capture.kind == "text_field" then
            local entry = context.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            if item then
                TextField.move_pointer(item, context.pointer_x, context.pointer_y, true)
            end
        end
        context:update_hover()
        return context.pointer_capture ~= nil
            or context:route_at(context.pointer_x, context.pointer_y).consumed
    elseif name == "mousepressed" then
        context.pointer_x, context.pointer_y = args[1], args[2]
        if context.input_mode_policy == "automatic" and context.selection_mode ~= "pointer" then
            return context:route_at(context.pointer_x, context.pointer_y).consumed
        end
        context:use_pointer_selection()
        if context.cancelled_pointer_button == args[3] then
            context.cancelled_pointer_button = nil
        end
        if args[3] == 1 then
            local scroll_entry, scroll_item =
                context:scrollbar_at(context.pointer_x, context.pointer_y)
            if scroll_item then
                local thumb = scroll_item.scrollbar_thumb
                local offset = thumb
                    and context.pointer_y >= thumb.y
                    and context.pointer_y <= thumb.y + thumb.h
                    and context.pointer_y - thumb.y
                    or nil
                context.pointer_capture = {
                    key = scroll_entry.key,
                    id = scroll_item.node.id,
                    kind = "scrollbar",
                    scrollbar_offset = offset,
                    start_x = context.pointer_x,
                    start_y = context.pointer_y,
                    last_x = context.pointer_x,
                    last_y = context.pointer_y,
                }
                context:set_scrollbar_pointer(
                    scroll_item,
                    context.pointer_y,
                    offset
                )
                return true
            end
        end
        local route = context:route_at(context.pointer_x, context.pointer_y)
        local item = route.item
        if args[3] == 1 and item and item.enabled then
            local handle = {key = route.entry.key, id = item.node.id}
            context.focused = item.kind == "text_field" and handle or nil
            context.pressed = {key = handle.key, id = handle.id}
            context.pointer_capture = {
                key = handle.key,
                id = handle.id,
                kind = item.kind,
                start_x = context.pointer_x,
                start_y = context.pointer_y,
                last_x = context.pointer_x,
                last_y = context.pointer_y,
                draggable = Gestures.draggable(item.node),
            }
            if item.kind == "slider" then
                context.pointer_capture.draggable = true
            end
            if item.kind == "text_field" then
                TextField.move_pointer(item, context.pointer_x, context.pointer_y, false)
            end
            context:queue(item.node.drag_started, item.node.id, {
                x = context.pointer_x,
                y = context.pointer_y,
                dx = 0,
                dy = 0,
                total_dx = 0,
                total_dy = 0,
            }, route.entry.key)
            context:queue(item.node.press_started, item.node.id,
                {input_source = "pointer"}, route.entry.key)
            if item.kind == "slider" then
                context:change_slider(
                    route.entry,
                    item,
                    context.pointer_x,
                    context.pointer_y,
                    "pointer"
                )
            elseif item.kind == "button" then
                if not context:start_hold(route.entry, item, "pointer") then
                    context:queue(item.node.action, item.node.id,
                        {input_source = "pointer"}, route.entry.key)
                end
            end
            context:update_hover()
            return true
        end
        context.focused = nil
        return route.consumed
    elseif name == "wheelmoved" then
        return context:scroll_at(
            context.pointer_x,
            context.pointer_y,
            args[1],
            args[2]
        ) or context:route_at(
            context.pointer_x,
            context.pointer_y
        ).consumed
    elseif name == "mousereleased" then
        context.pointer_x, context.pointer_y = args[1], args[2]
        if context.cancelled_pointer_button == args[3] then
            context.cancelled_pointer_button = nil
            context.pressed = nil
            context:update_hover()
            return true
        end
        local capture = context.pointer_capture
        if args[3] == 1 and capture then
            local entry = context.layers:get(capture.key)
            local item = entry and entry.layout.by_id[capture.id]
            local values = Gestures.drag_values(capture, context.pointer_x, context.pointer_y)
            context:release_hold(capture.key, capture.id)
            if item and capture.draggable then
                context:queue(item.node.drag_ended, item.node.id, values, entry.key)
            end
            if item then
                context:queue(item.node.press_ended, item.node.id,
                    {input_source = "pointer"}, entry.key)
            end
            context.pressed, context.pointer_capture = nil, nil
            context:update_hover()
            return true
        end
        return context:route_at(context.pointer_x, context.pointer_y).consumed
    elseif name == "keypressed" then
        local key = args[1]
        local owner = context:keyboard_owner()
        local entry = context.focused and context.layers:get(context.focused.key)
        local item = entry and owner == entry and entry.layout.by_id[context.focused.id]
        if item and item.enabled and item.kind == "text_field"
            and context:field_keypressed(entry, item, key)
        then
            return true
        end
        if key == "tab" then
            return context:focus_adjacent(context:modifiers().shift and -1 or 1)
        end
        if key == "up" or key == "down" or key == "left" or key == "right" then
            if context.semantic_drag then
                return context:set_semantic_drag_input(
                    {direction = key, phase = "pressed"}, "keyboard")
            end
            if context.keyboard_pressed and context.keyboard_pressed.semantic_drag then
                return true
            end
            return context:navigate(key, "keyboard")
        end
        if key == "space" or key == "return" or key == "kpenter" then
            return context:accept_selection("keyboard")
        end
        return owner ~= nil
    elseif name == "keyreleased" then
        local key = args[1]
        if context.semantic_drag
            and (key == "up" or key == "down" or key == "left" or key == "right")
        then
            return context:set_semantic_drag_input(
                {direction = key, phase = "released"}, "keyboard")
        end
        if context.navigation_input.drag_latched
            and (key == "up" or key == "down" or key == "left" or key == "right")
        then
            context.navigation_input = {x = 0, y = 0}
            return true
        end
        if context.keyboard_pressed
            and (key == "space" or key == "return" or key == "kpenter")
        then
            if context.keyboard_pressed.semantic then
                return context:release_selection("keyboard")
            end
            local pressed = context.keyboard_pressed
            local entry = context.layers:get(pressed.key)
            local item = entry and entry.layout and entry.layout.by_id[pressed.id]
            if item then
                context:queue(item.node.press_ended, item.node.id,
                    {input_source = "keyboard"}, entry.key)
            end
            context.keyboard_pressed, context.pressed = nil, nil
            return true
        end
        return context:keyboard_owner() ~= nil
    elseif name == "textinput" then
        local owner = context:keyboard_owner()
        local entry = context.focused and context.layers:get(context.focused.key)
        local item = entry and owner == entry and entry.layout.by_id[context.focused.id]
        if item and item.kind == "text_field" and item.enabled then
            if TextField.textinput(item.editor, args[1]) then
                context:emit_editor_change(entry, item)
            end
            return true
        end
        return owner ~= nil
    end
    return false
end

return InputRouter
