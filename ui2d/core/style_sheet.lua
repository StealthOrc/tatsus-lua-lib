local StyleSheet = {}
StyleSheet.__index = StyleSheet

local defaults = {
    viewport = {
        reference_width = 1920,
        reference_height = 1080,
        scale_mode = "contain",
        min_scale = 0.5,
        max_scale = 3,
        user_scale = 1,
    },
    root_font_size = 16,
    colors = {
        transparent = {0, 0, 0, 0},
        white = {1, 1, 1, 1},
        black = {0, 0, 0, 1},
    },
    fonts = {
        default = {},
    },
    text = {
        default = {
            font = "default",
            weight = "regular",
            size = 16,
            color = "white",
        },
    },
    space = {},
    radii = {},
    buttons = {
        default = {
            background = {0.15, 0.15, 0.17, 1},
            foreground = "white",
            min_height = 44,
            padding_x = 16,
            padding_y = 10,
            gap = 8,
            radius = 6,
            text = "default",
        },
    },
    text_fields = {
        default = {
            background = {0.08, 0.08, 0.10, 1},
            foreground = "white",
            selection = {0.18, 0.42, 0.92, 0.88},
            caret = "white",
            min_width = 180,
            min_height = 42,
            padding_x = 12,
            padding_y = 9,
            radius = 6,
            text = "default",
        },
    },
    sliders = {
        default = {
            track = {0.18, 0.18, 0.21, 1},
            fill = {0.35, 0.62, 1, 1},
            thumb = "white",
            thumb_selected = {0.72, 0.84, 1, 1},
            thumb_pressed = {0.55, 0.74, 1, 1},
            track_thickness = 6,
            thumb_size = 18,
        },
    },
}

local function copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return setmetatable(result, getmetatable(value))
end

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table"
            and not value.__ui2d_unit
            and type(target[key]) == "table"
            and not target[key].__ui2d_unit
        then
            merge(target[key], value)
        else
            target[key] = copy(value)
        end
    end
    return target
end

local function path_value(root, path)
    local current = root
    for part in tostring(path or ""):gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[part]
    end
    return current
end

function StyleSheet.new(config)
    if getmetatable(config) == StyleSheet then config = config.values end
    local values = merge(copy(defaults), config or {})
    return setmetatable({values = values}, StyleSheet)
end

function StyleSheet:get(path)
    return path_value(self.values, path)
end

function StyleSheet:token(value)
    if type(value) ~= "string" then
        return value
    end
    return self:get(value) or value
end

function StyleSheet:color(value)
    if type(value) == "string" then
        return self.values.colors[value] or self:get(value)
    end
    return value
end

function StyleSheet:text_style(name)
    name = name or "default"
    local base = copy(self.values.text.default or {})
    if name ~= "default" then
        merge(base, assert(self.values.text[name], "unknown text style: " .. tostring(name)))
    end
    return base
end

function StyleSheet:button_style(name)
    name = name or "default"
    local base = copy(self.values.buttons.default or {})
    if name ~= "default" then
        merge(base, assert(self.values.buttons[name], "unknown button style: " .. tostring(name)))
    end
    return base
end

function StyleSheet:text_field_style(name)
    name = name or "default"
    local base = copy(self.values.text_fields.default or {})
    if name ~= "default" then
        merge(base, assert(self.values.text_fields[name], "unknown text field style: " .. tostring(name)))
    end
    return base
end

function StyleSheet:slider_style(name)
    name = name or "default"
    local base = copy(self.values.sliders.default or {})
    if name ~= "default" then
        merge(base, assert(
            self.values.sliders[name],
            "unknown slider style: " .. tostring(name)
        ))
    end
    return base
end

function StyleSheet:viewport_scale(width, height)
    local viewport = self.values.viewport
    local width_scale = width / math.max(1, viewport.reference_width or width)
    local height_scale = height / math.max(1, viewport.reference_height or height)
    local scale
    if viewport.scale_mode == "width" then
        scale = width_scale
    elseif viewport.scale_mode == "height" then
        scale = height_scale
    elseif viewport.scale_mode == "cover" then
        scale = math.max(width_scale, height_scale)
    else
        scale = math.min(width_scale, height_scale)
    end
    scale = scale * (viewport.user_scale or 1)
    return math.max(viewport.min_scale or 0, math.min(viewport.max_scale or math.huge, scale))
end

function StyleSheet:with(overrides)
    if getmetatable(overrides) == StyleSheet then overrides = overrides.values end
    return setmetatable({values = merge(copy(self.values), overrides or {})}, StyleSheet)
end

function StyleSheet.interaction_state(states, name, seen)
    states = states or {}
    local state = states[name]
    if state == nil and name == "selected" then state = states.hovered end
    if type(state) ~= "string" then return state end
    seen = seen or {}
    if seen[state] then error("cyclic UI interaction state alias: " .. state) end
    seen[state] = true
    return StyleSheet.interaction_state(states, state, seen)
end

StyleSheet.copy = copy
StyleSheet.merge = merge

return StyleSheet
