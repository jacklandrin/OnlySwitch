# Pairing Code Copy Design

## Summary

Add an explicit copy action to the pairing-code row in the Mac app's **iOS Remote** settings. This keeps the code easy to transfer through the user's preferred secure channel without changing pairing, discovery, or code lifetime behavior.

## User Experience

- While a pairing window is active, show a **Copy** button beside the 12-character code.
- Pressing the button writes the exact code to the macOS pasteboard.
- After a successful copy, replace the button label with **Copied** briefly, then restore **Copy**.
- Keep the code non-selectable so there is one obvious copy interaction.
- Expose an accessible label that includes the action but does not announce the code unnecessarily.
- When pairing ends, clear the copied-feedback state along with the displayed code.

## Architecture

`RemoteAccessSettingsView` sends a `copyPairingCodeTapped` action. `RemoteAccessSettingsFeature` validates that a current code exists, writes it through an injected pasteboard dependency, and manages the temporary copied-feedback state with the feature clock. The view does not access `NSPasteboard.general` directly, keeping the side effect testable and consistent with TCA boundaries.

Clipboard write failure leaves the code visible and presents the settings feature's existing alert mechanism with a concise error. No network or credential state changes occur.

## Testing

Reducer tests will verify that:

- Copying writes the exact active pairing code.
- Copied feedback appears and clears after the configured delay.
- A stale copy action after pairing ends performs no pasteboard write.
- Copy failure presents an error without cancelling the pairing window.

The focused Mac settings tests and a Mac Release build will be run. The previously accepted Xcode 26.6 macOS test-scanner failure remains a baseline limitation if it prevents the focused test target from starting.
