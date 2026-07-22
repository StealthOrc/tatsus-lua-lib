function love.conf(config)
    config.window.title = "tatsus-lua-lib ui2d example"
    config.window.width = 960
    config.window.height = 540
    config.window.resizable = true
    config.console = true
    if os.getenv("UI2D_SMOKE") == "1" then
        config.window.visible = false
        config.modules.audio = false
        config.modules.sound = false
    end
end
