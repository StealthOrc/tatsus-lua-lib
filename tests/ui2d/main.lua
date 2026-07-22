package.path = "./?.lua;./?/init.lua;" .. package.path

local UI
local Units
local Svg

local passed = 0

local function close(actual, expected, message)
    if math.abs(actual - expected) > 0.001 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function test(name, body)
    body()
    passed = passed + 1
    print("PASS " .. name)
end

local function run()
    UI = require("ui2d")
    Units = require("ui2d.units")
    Svg = require("ui2d.svg")

    test("logical and relative units resolve explicitly", function()
        close(Units.resolve(12, 500, {scale = 1.5}), 18)
        close(Units.resolve(UI.percent(0.25), 500, {scale = 2}), 125)
        close(Units.resolve(UI.em(0.5), 500, {font_size = 30}), 15)
        close(Units.resolve(UI.rem(2), 500, {root_font_size = 24}), 48)
    end)

    test("stylesheet resolves contain scaling and named tokens", function()
        local styles = UI.StyleSheet {
            viewport = {reference_width = 800, reference_height = 600},
            space = {screen = 24},
        }
        close(styles:viewport_scale(1600, 900), 1.5)
        equal(styles:token("space.screen"), 24)
    end)

    test("compound SVG paths render with even-odd holes", function()
        local icon = Svg.parse([[
            <svg viewBox="0 0 20 20">
                <path fill="#fff" fill-rule="evenodd"
                    d="M0 0 L20 0 L20 20 L0 20 Z M5 5 L5 15 L15 15 L15 5 Z"/>
            </svg>
        ]])
        equal(#icon.items[1].paths, 2)
        equal(Svg.draw(icon, 0, 0, 20, 20), true)
    end)

    test("text editor keeps UTF-8 cursor positions intact", function()
        local editor = UI.TextEditor.new {value = "Héllo world"}
        equal(editor:length(), 11)
        editor:delete_backward(true)
        equal(editor:value(), "Héllo ")
        editor:insert("世界")
        equal(editor:value(), "Héllo 世界")
        equal(editor:length(), 8)

        editor:set_value("hello   world")
        editor:move_to(5)
        editor:delete_forward(true)
        equal(editor:value(), "hello")

        editor:set_value("hello   world")
        editor:move_to(5)
        editor:move(1, false, true)
        equal(editor.cursor, 13)
    end)

    test("declarative bottom-center button lays out and dispatches", function()
        local actions = {}
        local styles = UI.StyleSheet {
            viewport = {
                reference_width = 800,
                reference_height = 600,
                min_scale = 1,
                max_scale = 1,
            },
            colors = {
                screen = {0.02, 0.02, 0.03, 1},
                fire = {0.9, 0.15, 0.12, 1},
                on_fire = {1, 0.96, 0.9, 1},
            },
            space = {screen = 20, sm = 8},
            text = {
                action = {font = "default", size = 18, color = "on_fire"},
            },
            buttons = {
                primary = {
                    background = "fire",
                    foreground = "on_fire",
                    min_height = 50,
                    min_width = 150,
                    padding_x = 16,
                    padding_y = 10,
                    gap = "space.sm",
                    radius = 8,
                    text = "action",
                },
            },
        }
        local view = UI.view("fire", function()
            return UI.screen {
                background = "screen",
                padding = "space.screen",
                UI.button {
                    id = "fire",
                    anchor = "bottom-center",
                    style = "primary",
                    icon = "fire",
                    label = "Fire!",
                    action = {type = "fire"},
                },
            }
        end)
        local ui = UI.new {
            styles = styles,
            icons = {fire = "fixtures/fire.svg"},
            dispatch = function(action) actions[#actions + 1] = action end,
        }
        ui:show(view)
        ui:update(0)
        ui:draw()
        local rect = assert(ui:rect("fire"))
        close(rect.x + rect.w / 2, 400, "button is horizontally centered")
        close(rect.y + rect.h, 580, "button observes bottom padding")

        local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
        equal(ui:event("mousepressed", x, y, 1), true)
        equal(ui:event("mousereleased", x, y, 1), true)
        equal(#actions, 0, "actions dispatch during update")
        ui:update(0)
        equal(#actions, 1)
        equal(actions[1].type, "fire")
        equal(actions[1].source, "fire")

        ui:event("mousepressed", x, y, 1)
        ui:event("mousereleased", 1, 1, 1)
        ui:update(0)
        equal(#actions, 1, "release outside cancels activation")

        ui:event("keypressed", "tab")
        ui:event("keypressed", "space")
        ui:event("keyreleased", "space")
        ui:update(0)
        equal(#actions, 2, "focused button activates from keyboard")
    end)

    test("text field delegates editing and emits value actions", function()
        local actions = {}
        local view = UI.view("field", function()
            return UI.screen {
                padding = 20,
                UI.text_field {
                    id = "name",
                    value = "Hi",
                    changed = {type = "name_changed"},
                },
            }
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(view)
        ui:update(0)
        local rect = assert(ui:rect("name"))
        ui:event("mousepressed", rect.x + rect.w - 2, rect.y + rect.h / 2, 1)
        ui:event("mousereleased", rect.x + rect.w - 2, rect.y + rect.h / 2, 1)
        ui:event("textinput", " 👋")
        ui:update(0)
        equal(actions[#actions].type, "name_changed")
        equal(actions[#actions].value, "Hi 👋")
    end)

    test("row distributes remaining width by flex weight", function()
        local view = UI.view("flex", function()
            return UI.screen {
                UI.row {
                    width = "fill",
                    height = 100,
                    UI.panel {id = "one", flex = 1},
                    UI.panel {id = "two", flex = 2},
                },
            }
        end)
        local ui = UI.new()
        ui:show(view)
        ui:update(0)

        local one = assert(ui:rect("one"))
        local two = assert(ui:rect("two"))
        close(one.w, 800 / 3, "first flex child receives one share")
        close(two.w, 1600 / 3, "second flex child receives two shares")
        close(one.w + two.w, 800, "flex children fill the row")
    end)

    test("flex distribution respects minimum dimensions", function()
        local view = UI.view("flex-minimum", function()
            return UI.screen {
                UI.row {
                    width = "fill",
                    height = 100,
                    UI.panel {id = "minimum", flex = 1, min_width = 600},
                    UI.panel {id = "remainder", flex = 1},
                },
            }
        end)
        local ui = UI.new {styles = UI.StyleSheet {viewport = {min_scale = 1, max_scale = 1}}}
        ui:show(view)
        ui:update(0)
        close(ui:rect("minimum").w, 600)
        close(ui:rect("remainder").w, 200)
    end)

    test("a blocking View Layer prevents input from reaching lower layers", function()
        local actions = {}
        local hud = UI.view("hud", function()
            return UI.screen {
                UI.button {
                    id = "hud-action",
                    anchor = "center",
                    label = "HUD",
                    action = "hud_action",
                },
            }
        end)
        local menu = UI.view("menu", function()
            return UI.screen {background = {0, 0, 0, 0.5}}
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(hud, {key = "hud", layer = "base", pointer = "pass"})
        ui:push(menu, {key = "menu", layer = "overlay"})
        ui:update(0)

        local rect = assert(ui:rect("hud-action", "hud"))
        local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
        ui:event("mousemoved", x, y)
        equal(ui:event("mousepressed", x, y, 2), true, "blocking layer consumes non-primary buttons")
        equal(ui:event("wheelmoved", 0, 1), true, "blocking layer consumes wheel input")
        equal(ui:event("mousepressed", x, y, 1), true, "top layer consumes the press")
        equal(ui:event("mousereleased", x, y, 1), true, "top layer consumes the release")
        ui:update(0)
        equal(#actions, 0, "covered control is not activated")

        equal(ui:remove("menu"), true)
        ui:update(0)
        ui:event("mousepressed", x, y, 1)
        ui:event("mousereleased", x, y, 1)
        ui:update(0)
        equal(actions[#actions].type, "hud_action", "removing a layer reveals the lower control")
    end)

    test("a pass-through View Layer blocks only inside its panels", function()
        local actions = {}
        local menu = UI.view("menu", function()
            return UI.screen {
                UI.button {id = "top", anchor = "top-center", label = "Top", action = "top"},
                UI.button {id = "bottom", anchor = "bottom-center", label = "Bottom", action = "bottom"},
            }
        end)
        local drawer = UI.view("drawer", function()
            return UI.screen {
                UI.panel {
                    id = "drawer-panel",
                    anchor = "bottom-center",
                    width = "fill",
                    height = 200,
                    background = {0.1, 0.1, 0.1, 1},
                },
            }
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(menu, {key = "menu", layer = "base", pointer = "pass"})
        ui:push(drawer, {key = "drawer", layer = "popover", pointer = "pass"})
        ui:update(0)

        local top = assert(ui:rect("top", "menu"))
        local top_x, top_y = top.x + top.w / 2, top.y + top.h / 2
        ui:event("mousepressed", top_x, top_y, 1)
        ui:event("mousereleased", top_x, top_y, 1)
        ui:update(0)
        equal(actions[#actions].type, "top", "empty overlay area reaches the lower layer")

        local bottom = assert(ui:rect("bottom", "menu"))
        local bottom_x, bottom_y = bottom.x + bottom.w / 2, bottom.y + bottom.h / 2
        equal(ui:event("mousepressed", bottom_x, bottom_y, 1), true)
        equal(ui:event("mousereleased", bottom_x, bottom_y, 1), true)
        ui:update(0)
        equal(#actions, 1, "the panel blocks the lower button without emitting an action")
    end)

    test("stack Local Z-order controls both painting and hit routing", function()
        local actions = {}
        local view = UI.view("z-order", function()
            return UI.screen {
                UI.stack {
                    anchor = "center",
                    UI.button {id = "front", z = 10, label = "Front", action = "front"},
                    UI.button {id = "back", z = 0, label = "Back", action = "back"},
                },
            }
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(view)
        ui:update(0)
        local rect = assert(ui:rect("front"))
        local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
        ui:event("mousepressed", x, y, 1)
        ui:event("mousereleased", x, y, 1)
        ui:update(0)
        equal(actions[#actions].type, "front")
    end)

    test("visual transforms move rendering rectangles and Hit Regions together", function()
        local actions = {}
        local view = UI.view("transform", function()
            return UI.screen {
                UI.button {
                    id = "moving",
                    anchor = "center",
                    label = "Moving",
                    transform = {translate_x = 200},
                    action = "moving",
                },
            }
        end)
        local ui = UI.new {
            styles = UI.StyleSheet {viewport = {min_scale = 1, max_scale = 1}},
            dispatch = function(action) actions[#actions + 1] = action end,
        }
        ui:show(view, {pointer = "pass"})
        ui:update(0)

        local rect = assert(ui:rect("moving"))
        close(rect.x + rect.w / 2, 600, "reported rectangle follows the transform")
        equal(ui:event("mousepressed", 400, 300, 1), false, "old position is no longer interactive")
        equal(ui:event("mousepressed", 600, 300, 1), true)
        equal(ui:event("mousereleased", 600, 300, 1), true)
        ui:update(0)
        equal(actions[#actions].type, "moving")
    end)

    test("declarative transitions retarget from the current visual transform", function()
        local offset = 0
        local view = UI.view("animated", function()
            return UI.screen {
                UI.button {
                    id = "animated-button",
                    anchor = "center",
                    label = "Animated",
                    transform = {translate_x = offset},
                    transition = {transform = {duration = 1, ease = "linear"}},
                },
            }
        end)
        local ui = UI.new {styles = UI.StyleSheet {viewport = {min_scale = 1, max_scale = 1}}}
        ui:show(view, {pointer = "pass"})
        ui:update(0)

        offset = 100
        ui:update(0)
        close(ui:rect("animated-button").x + ui:rect("animated-button").w / 2, 400,
            "retargeting does not jump")
        ui:update(0.5)
        close(ui:rect("animated-button").x + ui:rect("animated-button").w / 2, 450,
            "transform reaches the midpoint")

        offset = 0
        ui:update(0)
        ui:update(0.5)
        close(ui:rect("animated-button").x + ui:rect("animated-button").w / 2, 400,
            "halfway reversal returns in the remaining half duration")
    end)

    test("hover style transitions reverse without restarting", function()
        local styles = UI.StyleSheet {
            viewport = {min_scale = 1, max_scale = 1},
            buttons = {
                hoverable = {
                    transform = {translate_y = 0},
                    states = {hovered = {transform = {translate_y = -20}}},
                    transition = {transform = {duration = 1, ease = "linear"}},
                },
            },
        }
        local view = UI.view("hover-motion", function()
            return UI.screen {
                UI.button {id = "hover-motion", anchor = "center", style = "hoverable", label = "Hover"},
            }
        end)
        local ui = UI.new {styles = styles}
        ui:show(view, {pointer = "pass"})
        ui:update(0)
        ui:event("mousemoved", 400, 300)
        ui:update(0)
        ui:update(0.5)
        local rect = ui:rect("hover-motion")
        close(rect.y + rect.h / 2, 290, "hover reaches the transition midpoint")

        ui:event("mousemoved", 0, 0)
        ui:update(0)
        ui:update(0.5)
        rect = ui:rect("hover-motion")
        close(rect.y + rect.h / 2, 300, "hover exit reverses from the current position")
    end)

    test("View Layer transitions animate entry and retain exit until completion", function()
        local base = UI.view("base", function() return UI.screen {} end)
        local overlay = UI.view("overlay", function()
            return UI.screen {
                UI.button {id = "overlay-button", anchor = "center", label = "Overlay"},
            }
        end)
        local ui = UI.new {styles = UI.StyleSheet {viewport = {min_scale = 1, max_scale = 1}}}
        ui:show(base, {pointer = "pass"})
        ui:push(overlay, {
            key = "overlay",
            layer = "overlay",
            transition = {
                from = {opacity = 0, transform = {translate_y = 100}},
                to = {opacity = 1, transform = {translate_y = 0}},
                duration = 1,
                ease = "linear",
            },
        })
        ui:update(0)
        close(ui:rect("overlay-button", "overlay").y + ui:rect("overlay-button", "overlay").h / 2,
            400, "entry begins at its from transform")
        ui:update(0.5)
        close(ui:rect("overlay-button", "overlay").y + ui:rect("overlay-button", "overlay").h / 2,
            350, "entry reaches its midpoint")

        equal(ui:remove("overlay"), true)
        equal(ui:rect("overlay-button", "overlay") ~= nil, true, "exiting layer is retained")
        ui:update(0.5)
        equal(ui:rect("overlay-button", "overlay"), nil, "layer unmounts after its exit")
    end)

    test("reopening an exiting View Layer reverses its current transition", function()
        local base = UI.view("base", function() return UI.screen {} end)
        local overlay = UI.view("reversible-overlay", function()
            return UI.screen {
                UI.button {id = "reversible-button", anchor = "center", label = "Overlay"},
            }
        end)
        local options = {
            key = "reversible-overlay",
            layer = "overlay",
            transition = {
                from = {transform = {translate_y = 100}},
                to = {transform = {translate_y = 0}},
                duration = 1,
                ease = "linear",
            },
        }
        local ui = UI.new {styles = UI.StyleSheet {viewport = {min_scale = 1, max_scale = 1}}}
        ui:show(base, {pointer = "pass"})
        ui:push(overlay, options)
        ui:update(0.5)
        ui:remove("reversible-overlay")
        ui:update(0.25)
        local rect = ui:rect("reversible-button", "reversible-overlay")
        close(rect.y + rect.h / 2, 375, "exit advances from the current entry position")

        ui:push(overlay, options)
        ui:update(0.25)
        rect = ui:rect("reversible-button", "reversible-overlay")
        close(rect.y + rect.h / 2, 350, "reopen reverses without jumping or restarting")
    end)

    test("hover enter and leave actions can drive tooltip View Layers", function()
        local actions = {}
        local view = UI.view("hover-actions", function()
            return UI.screen {
                UI.button {
                    id = "term",
                    anchor = "center",
                    label = "Term",
                    hover_enter = "show_tooltip",
                    hover_leave = "hide_tooltip",
                },
            }
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(view, {pointer = "pass"})
        ui:update(0)
        ui:event("mousemoved", 400, 300)
        ui:update(0)
        equal(actions[#actions].type, "show_tooltip")
        equal(actions[#actions].view, "hover-actions")

        ui:event("mousemoved", 0, 0)
        ui:update(0)
        equal(actions[#actions].type, "hide_tooltip")
    end)

    test("removing a captured View Layer consumes the pending release", function()
        local actions = {}
        local base = UI.view("capture-base", function() return UI.screen {} end)
        local overlay = UI.view("capture-overlay", function()
            return UI.screen {
                UI.button {id = "captured", anchor = "center", label = "Captured", action = "activate"},
            }
        end)
        local ui = UI.new {dispatch = function(action) actions[#actions + 1] = action end}
        ui:show(base, {pointer = "pass", keyboard = "pass"})
        ui:push(overlay, {key = "capture-overlay", pointer = "pass"})
        ui:update(0)
        local rect = ui:rect("captured", "capture-overlay")
        local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
        equal(ui:event("mousepressed", x, y, 1), true)
        ui:remove("capture-overlay")
        equal(ui:event("mousereleased", x, y, 1), true, "release cannot click through to the game")
        ui:update(0)
        equal(#actions, 0, "removed control is not activated")
    end)
end

function love.load()
    local ok, message = xpcall(run, debug.traceback)
    if ok then
        print(string.format("ui2d: %d tests passed", passed))
        os.exit(0)
    else
        print("ui2d test failure:\n" .. tostring(message))
        os.exit(1)
    end
end
