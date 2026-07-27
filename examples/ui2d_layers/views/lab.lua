local UI = require("ui2d")

local function sprite_row(model)
    local images = {}
    for index = 1, 10 do
        images[#images + 1] = UI.image {
            name = "demo_sprite",
            frame = (index + model.sprite_frame - 2) % 3 + 1,
            width = 34,
            height = 34,
            fit = "contain",
        }
    end
    return UI.flow {
        id = "sprite-flow",
        width = "fill",
        gap = 6,
        children = images,
    }
end

local function scroll_content()
    local entries = {}
    for index = 1, 12 do
        entries[#entries + 1] = UI.button {
            id = "scroll-entry-" .. index,
            width = "fill",
            height = 34,
            style = "compact",
            label = string.format("Scrollable entry %02d", index),
            action = {type = "select_scroll_entry", index = index},
        }
    end
    return UI.column {
        id = "scroll-demo",
        width = "fill",
        height = 126,
        gap = 4,
        overflow = "auto",
        scroll = {
            wheel = true,
            drag = true,
            scrollbar = "auto",
        },
        children = entries,
    }
end

return UI.view("lab", {
    styles = {
        colors = {
            lab_panel = {0.055, 0.07, 0.11, 0.99},
            lab_soft = {0.10, 0.12, 0.18, 1},
            lab_track = {0.18, 0.20, 0.27, 1},
            lab_fill = {0.31, 0.72, 1, 1},
        },
        buttons = {
            compact = {
                background = "lab_soft",
                foreground = "white",
                min_height = 34,
                padding_x = 10,
                padding_y = 5,
                radius = 5,
                text = "card_body",
            },
        },
        sliders = {
            demo = {
                track = "lab_track",
                fill = "lab_fill",
                thumb = "white",
                thumb_selected = "accent",
                track_thickness = 7,
                thumb_size = 20,
            },
        },
    },
    build = function(model)
        local tooltip = UI.tooltip {
            id = "media-tooltip",
            target = "demo-media",
            placement = model.tooltip_placement,
            collision = "flip",
            width = 250,
            padding = 12,
            radius = 7,
            background = "lab_soft",
            border = "accent",
            content = UI.text {
                value = "This tooltip prefers "
                    .. model.tooltip_placement
                    .. " and flips or shifts when it meets the viewport edge.",
                width = "fill",
                wrap = true,
                style = "card_body",
            },
        }
        return UI.screen {
            background = "world",
            padding = 24,
            UI.panel {
                anchor = "center",
                width = 760,
                height = 570,
                padding = 20,
                radius = 12,
                background = "lab_panel",
                border = "accent",
                border_width = 2,
                UI.column {
                    width = "fill",
                    height = "fill",
                    gap = 12,
                    overflow = "auto",
                    UI.row {
                        width = "fill",
                        align = "center",
                        UI.text {
                            value = "Fit-first UI2D lab",
                            style = "title",
                        },
                        UI.spacer {flex = 1},
                        UI.button {
                            id = "open-lab-modal",
                            style = "compact",
                            label = "Open modal",
                            action = "open_lab_modal",
                        },
                        UI.button {
                            id = "close-lab",
                            style = "compact",
                            label = "Close",
                            action = "close_lab",
                        },
                    },
                    UI.text {
                        value = "Images preserve their aspect ratio and fit their allocated box. Text wraps from measured font width. The controls below share pointer, keyboard, and controller behavior.",
                        width = "fill",
                        wrap = true,
                        style = "body",
                    },
                    UI.row {
                        width = "fill",
                        gap = 18,
                        align = "center",
                        UI.panel {
                            id = "demo-media",
                            width = 160,
                            height = 100,
                            padding = 6,
                            radius = 8,
                            background = "lab_soft",
                            border = "accent",
                            UI.image {
                                name = "demo_sprite",
                                frame = model.sprite_frame,
                                width = "fill",
                                height = "fill",
                                fit = "contain",
                            },
                        },
                        UI.column {
                            flex = 1,
                            gap = 7,
                            UI.text {
                                value = string.format(
                                    "Energy: %d%%",
                                    math.floor(model.energy * 100 + 0.5)
                                ),
                                style = "body",
                            },
                            UI.slider {
                                id = "energy-slider",
                                style = "demo",
                                width = "fill",
                                value = model.energy,
                                minimum = 0,
                                maximum = 1,
                                step = 0.05,
                                changed = "set_demo_energy",
                            },
                            UI.progress {
                                id = "energy-progress",
                                width = "fill",
                                height = 24,
                                value = model.energy,
                                maximum = 1,
                                label = "Animated progress",
                                background = "lab_track",
                                fill = "lab_fill",
                                text_style = "card_body",
                            },
                        },
                    },
                    UI.row {
                        width = "fill",
                        gap = 16,
                        align = "start",
                        UI.column {
                            flex = 1,
                            gap = 6,
                            UI.text {
                                value = "One Select, optional groups",
                                style = "body",
                            },
                            UI.select {
                                id = "resolution-select",
                                width = "fill",
                                value = model.resolution,
                                visible_count = 4,
                                button_style = "compact",
                                option_style = "compact",
                                selected_style = "motion",
                                list_background = "lab_soft",
                                list_border = "accent",
                                changed = "set_demo_resolution",
                                groups = {
                                    {
                                        label = "16:9",
                                        options = {
                                            {value = "1280x720", label = "1280 × 720"},
                                            {value = "1920x1080", label = "1920 × 1080"},
                                        },
                                    },
                                    {
                                        label = "Ultrawide",
                                        options = {
                                            {value = "2560x1080", label = "2560 × 1080"},
                                            {value = "3440x1440", label = "3440 × 1440"},
                                        },
                                    },
                                },
                            },
                        },
                        UI.column {
                            flex = 1,
                            gap = 6,
                            UI.text {
                                value = "Bounded overflow",
                                style = "body",
                            },
                            scroll_content(),
                        },
                    },
                    UI.text {
                        value = "Wrapping sprite flow",
                        style = "body",
                    },
                    sprite_row(model),
                    UI.segmented_control {
                        id = "tooltip-placement",
                        value = model.tooltip_placement,
                        options = {
                            {value = "auto", label = "AUTO"},
                            {value = "left", label = "LEFT"},
                            {value = "top", label = "TOP"},
                            {value = "right", label = "RIGHT"},
                            {value = "bottom", label = "BOTTOM"},
                        },
                        changed = "set_tooltip_placement",
                        button_style = "compact",
                        selected_style = "motion",
                        background = "lab_soft",
                        indicator_background = "accent",
                    },
                },
            },
            tooltip,
        }
    end,
})
