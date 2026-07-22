# tatsus-lua-lib

Shared vocabulary for the reusable LÖVE modules in this library.

## UI composition and input

**View**:
A declarative UI tree mounted as one independently managed piece of an interface.
_Avoid_: Screen, page

**View Layer**:
A mounted instance of a View with a stable identity and an ordering position in the UI.
_Avoid_: Modal, screen

**Layer Stack**:
The ordered collection of View Layers that together form the current UI.
_Avoid_: View list, modal stack

**Hit Region**:
A laid-out area that can receive or stop pointer input.
_Avoid_: Hitbox

**Hit Blocker**:
A Hit Region that consumes pointer input without requiring an interaction to occur.
_Avoid_: Invisible button, modal area

**Pass-through**:
The policy that allows pointer routing to continue to lower View Layers when no Hit Region handles or blocks the pointer position.
_Avoid_: Click-through, bubbling

**Local Z-order**:
The back-to-front ordering of overlapping nodes within one View Layer.
_Avoid_: Sublayer, global layer

## Animation and layout

**Motion Value**:
A retained current-and-target value whose interpolation may be redirected without discontinuity.
_Avoid_: Tween, when referring to the retained state rather than one transition segment

**Transition**:
The duration and easing policy used when a Motion Value moves from its current value to a target.
_Avoid_: Animation, tween

**Layout Geometry**:
The measured size and position that a container uses to arrange a node and its siblings.
_Avoid_: Transform, visual position

**Visual Transform**:
A post-layout translation, scale, or rotation that changes rendering and Hit Regions without changing sibling arrangement.
_Avoid_: Layout, offset
