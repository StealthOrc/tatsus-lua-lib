---
status: accepted
---

# Share target-driven Motion Values between game code and UI

The general `animation` module owns interruptible Motion Values and has no dependency on `ui2d`; the UI retains those values by View Layer, node identity, and property. UI movement defaults to post-layout Visual Transforms, and rendering and Hit Regions consume the same transform, avoiding continuous reflow while keeping interaction aligned with what the player sees.
