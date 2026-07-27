local Layout = require("ui2d.core.layout")
local Transform = require("ui2d.core.transform")
local RenderValues = require("ui2d.core.render_values")
local Button = require("ui2d.components.button")
local TextField = require("ui2d.components.text_field")
local Slider = require("ui2d.components.slider")

local Renderer = {}
Renderer.__index = Renderer

local color = RenderValues.color
local set_color = RenderValues.set_color

local function apply_transform(spec)
    love.graphics.translate(spec.translate_x, spec.translate_y)
    love.graphics.translate(spec.origin_x, spec.origin_y)
    love.graphics.rotate(spec.rotation)
    love.graphics.scale(spec.scale_x, spec.scale_y)
    love.graphics.translate(-spec.origin_x, -spec.origin_y)
end

local function primary_surface(item)
    if item.kind == "text" or item.kind == "icon"
        or item.kind == "image" then
        return "content"
    end
    return "background"
end

local function declared_surface(item, surface)
    local node_surfaces = item.node.shaders
    if node_surfaces and node_surfaces[surface] ~= nil then return node_surfaces[surface] end
    local style_surfaces = item.style and item.style.shaders
    if style_surfaces and style_surfaces[surface] ~= nil then return style_surfaces[surface] end
    if primary_surface(item) == surface and item.node.shader ~= nil then return item.node.shader end
    if primary_surface(item) == surface and item.style and item.style.shader ~= nil then return item.style.shader end
    return nil
end

local function media_tint(styles, value)
    if value == nil then return nil end
    if type(value) ~= "table" or value[1] ~= nil then
        return color(styles, value)
    end
    local result = {}
    for slot, slot_color in pairs(value) do
        result[slot] = color(styles, slot_color)
    end
    return result
end

local function draw_scrollbar(item, axis, layout, alpha)
    local vertical = axis == "vertical"
    local maximum = vertical and item.scroll_max_y or item.scroll_max_x
    if not maximum or maximum <= 0 then return end
    local thickness = math.max(3, 4 * layout.scale)
    local has_other = vertical
        and item.scroll_max_x and item.scroll_max_x > 0
        or not vertical and item.scroll_max_y and item.scroll_max_y > 0
    local viewport_rect = item.scroll_viewport_rect or item.rect
    local track = vertical and {
        x = viewport_rect.x + viewport_rect.w - thickness,
        y = viewport_rect.y,
        w = thickness,
        h = viewport_rect.h - (has_other and thickness or 0),
    } or {
        x = viewport_rect.x,
        y = viewport_rect.y + viewport_rect.h - thickness,
        w = viewport_rect.w - (has_other and thickness or 0),
        h = thickness,
    }
    local viewport = vertical and viewport_rect.h or viewport_rect.w
    local content = vertical
        and (item.inner_content_h or item.rect.h)
        or (item.inner_content_w or item.rect.w)
    local track_length = vertical and track.h or track.w
    local thumb_length = math.min(
        track_length,
        math.max(
            18 * layout.scale,
            track_length * viewport / math.max(viewport, content)
        )
    )
    local travel = math.max(0, track_length - thumb_length)
    local offset = (
        vertical and item.scroll_y or item.scroll_x
    ) / maximum * travel
    local thumb = vertical and {
        x = track.x,
        y = track.y + offset,
        w = thickness,
        h = thumb_length,
    } or {
        x = track.x + offset,
        y = track.y,
        w = thumb_length,
        h = thickness,
    }
    item.scrollbars = item.scrollbars or {}
    item.scrollbars[axis] = {
        track = track,
        thumb = thumb,
        visual_track = Transform.bounds(item.world_transform, track),
        visual_thumb = Transform.bounds(item.world_transform, thumb),
    }
    if vertical then
        item.scrollbar_track = track
        item.scrollbar_thumb = thumb
    end
    love.graphics.setColor(1, 1, 1, 0.18 * alpha)
    love.graphics.rectangle(
        "fill",
        track.x,
        track.y,
        track.w,
        track.h,
        thickness / 2,
        thickness / 2
    )
    love.graphics.setColor(1, 1, 1, 0.62 * alpha)
    love.graphics.rectangle(
        "fill",
        thumb.x,
        thumb.y,
        thumb.w,
        thumb.h,
        thickness / 2,
        thickness / 2
    )
end

function Renderer.new(styles, media, shaders)
    return setmetatable({
        styles = styles,
        icons = media,
        media = media,
        shaders = shaders,
    }, Renderer)
end

function Renderer:with_surface(spec, surface, item, context, layout, entry, alpha, draw)
    return self.shaders:with(spec, {
        surface = surface,
        item = item,
        context = context,
        layout = layout,
        entry = entry,
        alpha = alpha,
    }, draw)
end

function Renderer:radius(item, scale)
    local value = item.node.radius or (item.style and item.style.radius) or 0
    return Layout.resolve_length(value, math.min(item.rect.w, item.rect.h), {
        styles = item.styles or self.styles,
        scale = scale,
    }) or 0
end

function Renderer:border_width(item, scale)
    local value = item.node.border_width or (item.style and item.style.border_width) or 1
    return Layout.resolve_length(value, item.rect.w, {
        styles = item.styles or self.styles,
        scale = scale,
    }) or 1
end

function Renderer:draw_border(item, value, radius, scale, alpha, shader, environment)
    if not value then return end
    local styles = item.styles or self.styles
    local width = self:border_width(item, scale)
    self:with_surface(shader, "border", item, environment.context, environment.layout,
        environment.entry, alpha, function()
            love.graphics.setLineWidth(math.max(1, width))
            set_color(color(styles, value), alpha)
            love.graphics.rectangle("line", item.rect.x + width / 2, item.rect.y + width / 2,
                math.max(0, item.rect.w - width), math.max(0, item.rect.h - width), radius, radius)
        end)
end

function Renderer:container(item, scale, alpha, surfaces, environment)
    local styles = item.styles or self.styles
    local radius = self:radius(item, scale)
    if item.node.background then
        self:with_surface(surfaces.background, "background", item, environment.context,
            environment.layout, environment.entry, alpha, function()
                set_color(color(styles, item.node.background), alpha)
                love.graphics.rectangle("fill", item.rect.x, item.rect.y, item.rect.w, item.rect.h, radius, radius)
            end)
    end
    self:draw_border(item, item.node.border, radius, scale, alpha, surfaces.border, environment)
end

local function draw_item(self, item, context, layout, entry, inherited_alpha, inherited_content_shader)
    love.graphics.push()
    apply_transform(item.visual_transform)
    local alpha = inherited_alpha * item.visual_opacity
    local content_shader = declared_surface(item, "content") or inherited_content_shader
    local surfaces = {
        background = declared_surface(item, "background"),
        border = declared_surface(item, "border"),
        content = content_shader,
    }
    local state = {
        hovered = context:is_hovered(entry, item.node.id),
        selected = context:is_selected(entry, item.node.id),
        pressed = context:is_pressed(entry, item.node.id),
        focused = context:is_focused(entry, item.node.id),
        holding = context:is_holding(entry, item.node.id),
        hold_progress = context:hold_progress(item.node.id, entry.key),
    }
    item.hold_progress = state.hold_progress
    local environment = {context = context, layout = layout, entry = entry}
    if item.kind == "screen" or item.kind == "panel" or item.kind == "row"
        or item.kind == "column" or item.kind == "flow"
        or item.kind == "stack"
    then
        self:container(item, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "button" then
        Button.draw(self, item, state, layout.scale, alpha, surfaces, environment)
    elseif item.kind == "text_field" then
        TextField.draw(self, item, state,
            layout.scale, context.time, alpha, surfaces, environment)
    elseif item.kind == "slider" then
        Slider.draw(
            self,
            item,
            state,
            layout.scale,
            alpha,
            surfaces,
            environment
        )
    elseif item.kind == "text" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            love.graphics.setFont(item.font)
            set_color(color(item.styles or self.styles,
                item.node.color or item.text_style.color), alpha)
            for index, line in ipairs(item.lines or {item.text}) do
                local x = item.rect.x
                if item.node.align == "center" then
                    x = item.rect.x
                        + (item.rect.w - item.font:getWidth(line)) / 2
                elseif item.node.align == "right" then
                    x = item.rect.x + item.rect.w
                        - item.font:getWidth(line)
                end
                local y = item.rect.y
                    + (index - 1) * (item.line_advance or item.font:getHeight())
                love.graphics.print(
                    line,
                    math.floor(x + 0.5),
                    math.floor(y + 0.5)
                )
            end
        end)
    elseif item.kind == "icon" or item.kind == "image" then
        self:with_surface(surfaces.content, "content", item, context, layout, entry, alpha, function()
            local tint = media_tint(
                item.styles or self.styles,
                item.node.tint
            )
            self.media:draw(
                item.media_name,
                item.rect.x,
                item.rect.y,
                item.rect.w,
                item.rect.h,
                tint,
                (item.node.alpha or 1) * alpha,
                item.node
            )
        end)
    end
    local clips_children = item.clips_children
    local previous_scissor
    if clips_children then
        previous_scissor = {love.graphics.getScissor()}
        local clip = item.visual_child_clip_rect
        if clip then
            love.graphics.setScissor(clip.x, clip.y, clip.w, clip.h)
        end
    end
    for _, child in ipairs(item.children or {}) do
        draw_item(self, child, context, layout, entry, alpha, content_shader)
    end
    if clips_children then
        if previous_scissor[1] then
            love.graphics.setScissor(
                previous_scissor[1],
                previous_scissor[2],
                previous_scissor[3],
                previous_scissor[4]
            )
        else
            love.graphics.setScissor()
        end
    end
    local scroll_options = type(item.node.scroll) == "table"
        and item.node.scroll
        or {}
    if scroll_options.scrollbar ~= "hidden" then
        item.scrollbars = {}
        draw_scrollbar(item, "vertical", layout, alpha)
        draw_scrollbar(item, "horizontal", layout, alpha)
    end
    love.graphics.pop()
end

function Renderer:draw(layout, context, entry)
    if not layout then return end
    love.graphics.push("all")
    love.graphics.origin()
    if layout.layer_visual_transform then apply_transform(layout.layer_visual_transform) end
    draw_item(self, layout.root, context, layout, entry, layout.layer_opacity or 1, nil)
    love.graphics.pop()
end

return Renderer
