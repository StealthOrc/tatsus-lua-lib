---
status: accepted
---

# Route UI input through ordered View Layers and spatial Hit Blockers

`ui2d` will render mounted View Layers from back to front and route pointer input through the exact reverse of that same order. View Layers block input across their bounds by default, pass-through is explicit, interactive nodes consume automatically, and panels may create spatial Hit Blockers; this supports full-screen views, partial overlays, and tooltips without maintaining separate render and input hierarchies that could disagree.
