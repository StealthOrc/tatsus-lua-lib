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
