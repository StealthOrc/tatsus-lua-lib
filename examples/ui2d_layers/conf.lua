function love.conf(config)
    config.window.title = "UI in Motion · tatsus-lua-lib ui2d"
    config.window.width = 960
    config.window.height = 640
    config.window.resizable = true
    config.console = true
    if os.getenv("UI2D_SMOKE") == "1" then config.window.visible = false end
end
