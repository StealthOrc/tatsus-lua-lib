local UI = require("ui2d")

local function fluid(seed, cursed, brightness)
    return {
        name = "perk_fluid",
        uniforms = {
            seed = seed,
            cursed = cursed and 1 or 0,
            brightness = brightness or 0,
            hex_radius = 3.2,
        },
    }
end

local function card(spec)
    local shader = spec.shader
    local title = UI.text {
        anchor = "center",
        value = spec.title,
        style = shader and "card_title" or "paper_title_inverse",
        shader = spec.title_shader,
    }
    title = UI.panel {
        width = 196,
        height = 34,
        radius = 5,
        background = shader and "world" or "parchment_border",
        title,
    }
    return UI.panel {
        width = 238,
        height = 292,
        padding = 16,
        radius = 12,
        background = spec.background,
        border = spec.border,
        border_width = 3,
        shaders = shader and {background = shader, border = shader} or nil,
        UI.column {
            anchor = "center",
            align = "center",
            gap = 14,
            title,
            UI.text {value = spec.rarity, style = shader and "card_body" or "paper_body"},
            UI.spacer {height = 4},
            UI.text {value = spec.line_one, style = shader and "card_body" or "paper_body"},
            UI.text {value = spec.line_two, style = shader and "card_body" or "paper_body"},
            UI.spacer {height = 8},
            UI.text {value = spec.effect, style = shader and "card_title" or "paper_title"},
        },
    }
end

return UI.view("drawer", {
    styles = {
        colors = {
            world = {0.025, 0.04, 0.065, 1},
            panel = {0.09, 0.11, 0.17, 1},
            drawer_handle = {0.13, 0.15, 0.22, 1},
        },
        buttons = {
            drawer_handle = {
                background = "drawer_handle",
                background_hovered = {0.20, 0.23, 0.32, 1},
                background_pressed = {0.26, 0.29, 0.38, 1},
                foreground = "white",
                min_width = 168,
                min_height = 26,
                padding_x = 18,
                padding_y = 3,
                radius = 13,
                text = "card_body",
            },
        },
    },
    build = function(model)
        local progress = math.max(0, math.min(1, model.progress or 0.67))
        local expanded = progress < 0.335
        local prismatic = fluid(17, false)
        local cursed = fluid(117, true)

        return UI.screen {
            UI.panel {
                id = "drawer-panel",
                anchor = "bottom-center",
                width = "fill",
                height = "fill",
                padding = 24,
                background = "panel",
                border = "accent",
                border_width = 2,
                transform = {translate_y = UI.percent(progress)},
                transition = {
                    transform = {
                        duration = model.dragging and 0
                            or (model.settle_duration or 0.38),
                        ease = "out_cubic",
                    },
                },
                UI.column {
                    anchor = "top-center",
                    width = "fill",
                    align = "center",
                    gap = 12,
                    UI.button {
                        id = "drawer-grab-handle",
                        style = "drawer_handle",
                        label = "=  DRAG DRAWER  =",
                        semantic_drag = {
                            mode = "flick",
                            axis = "vertical",
                            max_distance = 92,
                            response = 20,
                            flick_threshold = 8,
                        },
                        drag_started = "drawer_drag_start",
                        dragged = "drawer_drag_move",
                        drag_ended = "drawer_drag_end",
                    },
                    UI.text {
                        value = "This panel blocks only the part currently visible.",
                        style = "body",
                    },
                    UI.row {
                        width = "fill",
                        justify = "center",
                        gap = 12,
                        styles = {
                            colors = {
                                accent = {0.72, 0.32, 0.96, 1},
                            },
                        },
                        UI.button {
                            id = "tooltip-term",
                            style = "motion",
                            label = "Tooltip: " .. model.tooltip_mode
                                .. (model.tooltip_mode == "pointer"
                                    and model.active_tooltip_mode == "button"
                                    and " (selection)" or ""),
                            action = "cycle_tooltip_anchor",
                            hover_enter = "show_tooltip",
                            hover_leave = "hide_tooltip",
                            select_enter = "show_tooltip",
                            select_leave = "hide_tooltip",
                        },
                        UI.button {
                            id = "toggle-perks",
                            style = "motion",
                            label = expanded
                                and "Lower drawer" or "Pull drawer further up",
                            action = expanded and "close_perks" or "open_perks",
                        },
                        UI.button {
                            id = "close-drawer",
                            style = "motion",
                            label = "Close drawer",
                            action = "close_drawer",
                        },
                    },
                    UI.text {
                        value = "Shader Surfaces / Perk Draft",
                        style = "title",
                    },
                    UI.text {
                        value = "These cards always live below the controls in this same view.",
                        style = "body",
                    },
                    UI.row {
                        width = "fill",
                        justify = "center",
                        gap = 18,
                        card {
                            title = "Steady Hand",
                            rarity = "NORMAL PERK",
                            background = "parchment",
                            border = "parchment_border",
                            line_one = "Reliable power with",
                            line_two = "no strange conditions.",
                            effect = "+12% precision",
                        },
                        card {
                            title = "Star Bloom",
                            rarity = "PRISMATIC PERK",
                            background = "white",
                            border = "white",
                            shader = prismatic,
                            title_shader = fluid(61, false, 0.52),
                            line_one = "The card, border, and title",
                            line_two = "use separate shader surfaces.",
                            effect = "+2 all stats",
                        },
                        card {
                            title = "Blood Price",
                            rarity = "CURSED PERK",
                            background = "white",
                            border = "white",
                            shader = cursed,
                            title_shader = fluid(161, true, 0.52),
                            line_one = "Great power, paid for",
                            line_two = "whenever you are hit.",
                            effect = "+40% damage",
                        },
                    },
                },
            },
        }
    end,
})
