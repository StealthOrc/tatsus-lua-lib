---
status: accepted
---

# Separate semantic UI navigation from device-aware Input Bindings

`ui2d` will own Selection, automatic Navigation Groups, selected/hovered/pressed visual states, and semantic `navigate` and `accept` input, but it will not choose physical keys, buttons, or axes. The independent `input` module will map keyboard and gamepad controls into Input Actions using separate Binding Sets and will not depend on `ui2d`; games connect the two through a small semantic adapter, allowing either module to be used without the other.
