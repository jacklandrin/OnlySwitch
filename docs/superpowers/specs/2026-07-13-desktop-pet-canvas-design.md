# Desktop Pet Canvas Design

## Goal

Remove the hard clipping visible at the left and right edges of the desktop pet's blue glow, while also giving the legs, ground shadow, breathing motion, and drag scale enough vertical drawing space.

## Root Cause

The visible artwork is designed inside a `120 × 130` point window. The body is 108 points wide and uses a 10- to 14-point shadow, while the arms extend close to or beyond the 120-point horizontal boundary. Vertically, the legs and ground shadow reach almost to the 130-point boundary; breathing and the 1.04 drag scale can move them outside it. SwiftUI cannot render beyond the transparent `NSPanel` bounds, so those pixels end at a hard edge.

## Selected Design

- Expand only the transparent desktop-pet panel and SwiftUI root canvas to `152 × 160` points.
- Keep the vector artwork's existing `120 × 130` coordinate space, body dimensions, limb positions, glow radius, and animation amplitudes unchanged.
- Center the artwork inside the larger canvas, providing 16 points of horizontal and 15 points of vertical transparent padding.
- Keep the panel background transparent and preserve the existing draggable hit area and always-on-top behavior.
- Compensate the default panel origin for the added transparent padding so the original `120 × 130` artwork boundary remains 24 points from the screen's left and bottom visible edges.

## Saved-Position Migration

An existing autosaved frame may still be `120 × 130`. After restoring it, resize it to `152 × 160` while preserving its center point. This keeps the visible pet centered at the user's prior desktop location. Then constrain the enlarged frame to the selected screen's visible frame and save the updated frame.

## Components

- `DesktopPetView` owns the expanded root frame and centers the unchanged artwork coordinate space inside it.
- `DesktopPetController` creates the panel using the expanded size and applies the compensated default origin.
- `DesktopPetLayout` provides pure geometry for calculating asymmetric default insets and resizing a restored frame around its center.

## Testing and Verification

- A layout test verifies that the compensated default panel origin keeps the artwork boundary 24 points from the left and bottom.
- A layout test verifies that resizing a legacy `120 × 130` frame to `152 × 160` preserves its center.
- Existing position, screen selection, drag, and presentation-state tests continue to pass.
- The complete Modules test suite and strict-concurrency OnlySwitch build must pass.
- Visual verification confirms that the left/right blue glow and bottom legs/ground shadow fade naturally before the transparent window boundary in idle, open, breathing, and dragging states.

## Scope

This change does not alter the visible pet size, vector design, glow strength, animation timing, Only Control behavior, or preference behavior.
