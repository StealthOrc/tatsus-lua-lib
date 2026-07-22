---
status: accepted
---

# Capture semantic navigation vectors while dragging

`ui2d` will let an accepted drag handle enter Semantic Drag Capture, during which navigation vectors produce drag lifecycle actions instead of changing Selection. Handles may choose continuous motion or a bounded flick gesture that reports velocity without permitting unlimited controller travel. Releasing accept ends capture and temporarily suppresses navigation until an analog vector returns to neutral; this keeps pointer and controller dragging behind the same node interface without making UI2D choose physical controller inputs.
