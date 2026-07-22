# iPhone Landscape Dashboard Grid Design

## Goal

Show more dashboard tiles per row when OnlySwitch Remote runs on an iPhone in landscape, while preserving the existing portrait and iPad layouts and keeping tile content readable.

## Layout Rules

- iPhone portrait remains a fixed two-column grid.
- A vertically compact layout, which represents iPhone landscape, uses adaptive columns with a minimum tile width of 180 points.
- Smaller landscape iPhones therefore show three columns; wider current iPhones show four.
- iPad and other regular-height layouts retain the existing adaptive grid with a 160-point minimum.
- Grid spacing remains 12 points.

The layout will use SwiftUI size classes rather than device-model checks or direct orientation notifications. This allows the grid to respond correctly to rotation, multitasking, and future screen sizes.

## Components

`DashboardView` will read both horizontal and vertical size classes. A small, pure column-strategy helper will map those size classes to portrait, iPhone-landscape, or regular adaptive grid rules. `LazyVGrid` and `ControlTileView` remain otherwise unchanged.

## Accessibility and Content

Dynamic Type, VoiceOver labels, tile actions, status accessories, secondary information, and unavailable explanations remain unchanged. The 180-point landscape minimum protects multi-line titles and explanations from the more aggressive five-column layout that a 160-point minimum could produce on a wide iPhone.

## Testing

Add focused tests for the pure grid strategy:

- compact width and regular height produces two columns;
- compact height produces an adaptive 180-point landscape grid;
- regular layouts preserve the existing adaptive 160-point grid.

Run the full dashboard tests and iOS Remote test target, then build, install, and launch on the connected iPhone. Physical acceptance verifies two columns in portrait and three or four columns in landscape without clipped tile content.

## Out of Scope

- Changing tile height, internal padding, font sizes, or icon sizes.
- Changing iPad density.
- Adding user-configurable column counts.
- Detecting specific iPhone models.
