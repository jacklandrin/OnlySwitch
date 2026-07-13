# Desktop Pet Design

## Goal

Add an optional, always-on-top desktop companion to OnlySwitch. The companion is an original anthropomorphic switch mascot drawn with SwiftUI. It can be dragged around the desktop, remembers its position, and opens Only Control when clicked.

The pet is hidden by default. Users show or hide it with a toggle in General settings.

## Chosen Design

The pet is a small, code-drawn SwiftUI character with a rounded toggle-shaped body, a luminous slider face, short arms and legs, and an OnlySwitch blue-to-violet palette. Its silhouette and details are original rather than a copy of the ChatGPT reference. The rendered size is approximately 110 by 120 points, close to the perceived size of the reference desktop pet.

The idle state uses restrained breathing, blinking, and occasional slider movement. Animation pauses while the user drags the pet. When Reduce Motion is enabled, the pet remains static apart from immediate interaction feedback.

Clicking the pet always shows or raises Only Control. It does not read or change the selected menu-bar appearance, so Single Column and Two Columns continue to work unchanged from the menu-bar item.

## Module Boundary

Create an independent `DesktopPet` library product and target in `Modules/Package.swift`. The module depends only on AppKit and SwiftUI.

The module owns:

- `DesktopPetView`, including the vector artwork and animation phases.
- `DesktopPetController`, a `@MainActor` owner for the transparent floating panel.
- Drag-versus-click interaction handling.
- Frame restoration, visible-screen clamping, and display-change handling.
- Small internal value types and pure layout functions needed for testing.

The module exposes a narrow controller API: construct it with an activation closure, then call `show()` or `hide()`. It has no dependency on Only Control, app preferences, switch models, or Composable Architecture. The main app supplies a closure that calls `OnlyControlWindow.shared.show()`.

OnlySwitch owns:

- The `showDesktopPet` preference, whose default is `false`.
- The General settings toggle and localized label.
- Startup and preference-change wiring between `AppDelegate` and `DesktopPetController`.
- The concrete activation closure that opens Only Control.

This boundary keeps the visual feature reusable and prevents the module from reaching back into app-specific singleton state.

## Window and Interaction Behavior

The controller hosts the SwiftUI view in a transparent, borderless, non-activating `NSPanel`. The panel floats above normal app windows, does not appear in the Dock or window switcher, stays visible when OnlySwitch is inactive, and can join every Space, including full-screen auxiliary spaces.

A short pointer movement is treated as a click and invokes the activation closure. Movement beyond the drag threshold moves the panel and suppresses activation on release. The panel is constrained to the usable bounds of the screen containing most of it, leaving the complete mascot reachable.

AppKit frame autosaving stores the last position. On show, launch, screen-resolution changes, or monitor removal, the controller restores the saved frame and clamps it to an available visible frame. If no valid saved position exists, the pet starts near the lower-right corner of the main screen with a comfortable inset.

Showing the pet repeatedly is idempotent. Hiding it immediately removes it from view without destroying the controller or losing its saved position. Clicking while Only Control is already visible raises that window through its existing `show()` behavior.

## Settings and Data Flow

`Preferences.showDesktopPet` uses the existing `@UserDefaultValue` pattern and defaults to `false`. Its setter posts a dedicated notification on the main queue.

At launch, `AppDelegate` creates one `DesktopPetController` and passes the Only Control activation closure. It shows the panel only when the stored preference is enabled. The notification observer calls `show()` or `hide()` immediately when the General settings toggle changes.

No pet visibility state is duplicated in SwiftUI. UserDefaults is the persisted source of truth, while the controller's panel visibility is the runtime projection of that preference.

## Accessibility and Energy Use

The pet exposes one accessibility button labeled “Open Only Control” and a help description indicating that it can be dragged. Decorative body parts are hidden from the accessibility tree.

Animation uses SwiftUI state-driven transforms rather than a continuously rendered sprite or external animation engine. Timers stop when the pet is hidden, and drag state suspends idle animation. The view observes Reduce Motion and disables nonessential movement.

## Error and Edge Handling

- If a saved frame is malformed or off-screen, fall back to a clamped default position.
- If the active display disappears, move the pet onto the nearest available visible frame.
- If no screen is temporarily available, retain the current frame and retry positioning the next time the panel is shown or display configuration changes.
- Repeated show, hide, and display-change notifications must not create additional panels or observers.

The feature has no network, file, image-generation, or third-party runtime dependency.

## Testing

Module unit tests cover:

- Default placement within a screen's visible frame.
- Clamping frames that extend beyond each screen edge.
- Restoring a valid saved frame unchanged.
- Selecting an appropriate screen in multi-display layouts.
- The pointer-distance threshold that distinguishes a click from a drag.

App-level tests cover the preference default and the preference-to-controller visibility decision where practical. Manual verification covers dragging, saved position across relaunch, switching Spaces, removing a monitor, opening an already-visible Only Control window, Reduce Motion, light and dark appearance, and toggling the pet on and off in General settings.

The final verification builds the `Modules` package and the OnlySwitch macOS app.

## Alternatives Considered

1. Draw and animate the mascot with SwiftUI. This is selected because it scales cleanly on Retina displays, supports independent motion of facial and switch elements, adapts to accessibility settings, and adds no dependency.
2. Assemble the mascot from layered PNG artwork. This permits painterly detail but makes scaling, recoloring, and animation less flexible and introduces asset-generation and maintenance work.
3. Use a Lottie or Rive animation. This provides sophisticated motion but introduces a new runtime dependency and authoring format for a deliberately small, subtle companion.

## Scope

This feature adds one optional desktop pet, its General settings toggle, and the wiring required to open the existing Only Control window. It does not replace the menu-bar icon, change menu appearance behavior, add multiple pets or skins, add speech or AI behavior, or redesign Only Control.
