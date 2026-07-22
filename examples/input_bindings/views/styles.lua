local UI = require("ui2d")

return UI.StyleSheet {
    viewport = {
        reference_width = 1100,
        reference_height = 720,
        min_scale = 0.68,
        max_scale = 2,
    },
    colors = {
        transparent = {0, 0, 0, 0},
        accent = {0.16, 0.90, 1.00, 1},
        ink = {0.018, 0.035, 0.045, 1},
        text = {0.92, 0.96, 1.00, 1},
        muted = {0.54, 0.63, 0.73, 1},
        white = {1, 1, 1, 1},
    },
    text = {
        display = {size = 30, color = "text"},
        title = {size = 22, color = "text"},
        body = {size = 16, color = "text"},
        binding = {size = 15, color = "accent"},
        label = {size = 12, color = "muted"},
        small = {size = 13, color = "muted"},
    },
}
