function love.conf(config)
    config.window.title = "tatsus-lua-lib ui2d layers and motion"
    config.window.width = 960
    config.window.height = 640
    config.window.resizable = true
    config.console = true
    if os.getenv("UI2D_SMOKE") == "1" then config.window.visible = false end
end
