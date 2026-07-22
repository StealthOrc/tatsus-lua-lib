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

**Selection**:
The one navigable UI element currently targeted for semantic activation. Pointer hover presents the same selected state while pointer input is active, without erasing retained controller selection.
_Avoid_: Focus, when referring to controller navigation

**Navigation Group**:
A container relationship used to choose the next Selection. Rows and columns infer horizontal and vertical groups; compatible sibling groups can preserve child ordinal.
_Avoid_: Tab order, focus chain

**Semantic Input**:
A device-independent intention such as navigate or accept that UI2D can consume without knowing which physical control produced it.
_Avoid_: Key event, controller event

**Semantic Drag Capture**:
The state entered when a selected drag handle is held through Semantic Input; navigation vectors become drag motion until accept is released, so Selection cannot escape mid-drag.
_Avoid_: Controller mode, virtual mouse

**Input Action**:
A named gameplay or UI intention with a declared value shape: button, one-dimensional axis, or two-dimensional axis.
_Avoid_: Hotkey

**Binding Set**:
The bindings for one device family, such as keyboard or gamepad. Changing one Binding Set does not overwrite another.
_Avoid_: Control scheme, when referring specifically to stored bindings

**Binding**:
A recipe that maps one or more physical or standardized controls to an Input Action. Chords, axis directions, full axes, sticks, and digital composites are all Binding shapes.
_Avoid_: Key, when the source may not be a keyboard key

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
