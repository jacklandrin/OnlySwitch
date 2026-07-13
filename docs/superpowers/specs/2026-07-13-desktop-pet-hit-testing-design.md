# Desktop Pet Hit-Testing Repair Design

## Goal

Restore reliable desktop-pet clicking and dragging without making the transparent glow padding intercept mouse input.

## Root Cause

The canvas expansion moved the drag gesture from the rendered `DesktopPetView` to a separate `Color.clear` sibling inside a `ZStack`, while disabling hit testing on the rendered view. In the actual `NSHostingView` hosted by the nonactivating `NSPanel`, that fully transparent sibling does not provide the same reliable mouse-event path as the previously working rendered view, so drag callbacks are no longer delivered.

## Selected Design

- Remove the transparent gesture sibling and remove `.allowsHitTesting(false)` from `DesktopPetView`.
- Attach the existing zero-distance `DragGesture` directly to `DesktopPetView`, restoring the previously working event path.
- Add a dedicated `DesktopPetInteractionShape` conforming to SwiftUI `Shape`.
- The shape returns a centered `120 × 130` rectangle when evaluated inside the `152 × 160` canvas.
- Apply the shape with `.contentShape(.interaction, ...)` so the 16-point horizontal and 15-point vertical glow padding remains non-interactive.
- Keep all canvas sizes, artwork dimensions, shadows, animation, window positioning, Only Control behavior, and drag calculations unchanged.

## Testing and Verification

- Add a Swift Testing assertion that the interaction shape's path bounds equal `CGRect(x: 16, y: 15, width: 120, height: 130)` inside the expanded canvas.
- Run the focused DesktopPet tests and the complete Modules test suite.
- Run the OnlySwitch build with strict concurrency enabled.
- Launch the Debug app and verify that dragging from the visible pet moves the panel, clicking still toggles Only Control, and clicking in the outer transparent padding does nothing.

## Scope

This repair changes only SwiftUI hit testing. It does not modify the pet's appearance or window geometry.
