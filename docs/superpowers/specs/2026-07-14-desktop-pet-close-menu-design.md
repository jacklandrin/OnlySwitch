# Desktop Pet Close Menu Design

## Goal

Let the user right-click the desktop pet and choose **Close**. Closing the pet permanently turns off **General → Show Desktop Pet** until the user enables that setting again.

## User Experience

- Right-clicking within the pet's existing interaction area opens a context menu.
- The menu contains one destructive action labeled **Close**.
- Choosing **Close** immediately hides the desktop pet without confirmation.
- Closing the pet sets the existing `showDesktopPet` preference to `false`, so the pet stays hidden after relaunch.
- The existing General setting remains the only way to show the pet again.
- Existing left-click activation and drag-to-move behavior remain unchanged.

## Architecture

`DesktopPetRootView` owns the SwiftUI context menu because it already defines the pet's interactive region. It receives an `onClose` callback from `DesktopPetController` and invokes that callback from the menu action.

`DesktopPetController` accepts and forwards `onClose` without depending on OnlySwitch preferences. This preserves the `DesktopPet` module's independence from app-level settings.

`AppDelegate` supplies an `onClose` callback that sets `Preferences.shared.showDesktopPet` to `false`. The preference's existing notification causes `desktopPetVisibilityDidChange()` to call `DesktopPetController.hide()`, keeping visibility changes on the established path.

## Error Handling

The close operation is synchronous and uses the existing preference and notification flow. It introduces no new recoverable failure path. If the controller has already been released, its view and callback are released with it.

## Testing

- Add a module test proving that the controller's close request invokes its supplied close callback.
- Keep the existing app preference test as coverage that changing `showDesktopPet` publishes the visibility notification and persists the value.
- Run the DesktopPet module tests and build the OnlySwitch app to catch integration or concurrency errors.

## Scope

No additional menu items, confirmation dialog, keyboard shortcut, localization expansion, or changes to desktop-pet animation and layout are included.
