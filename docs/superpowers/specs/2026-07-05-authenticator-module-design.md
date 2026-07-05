# Authenticator Module Design

## Goal

Move the Authenticator feature into the existing SwiftPM package under `Modules` while keeping `AuthenticatorSwitch` in the app target as the app-specific switch adapter.

## Current Shape

Authenticator code currently lives in the app target across two feature folders:

- `OnlySwitch/Features/Authenticator`: core models, TOTP generation, Base32 decoding, Google Authenticator import parsing, protobuf reading, and the popover panel view.
- `OnlySwitch/Features/Settings/Authenticator`: store, import sheet, and settings view.
- `OnlySwitch/EverySwitch/AuthenticatorSwitch.swift`: switch integration that reads `AuthenticatorStore` state and toggles display.

The repository already uses `Modules/Package.swift` for reusable feature modules such as `PureColorView` and `StickerView`, and the app target links those products directly.

## Approved Boundary

Create a new SwiftPM library product and target named `Authenticator`.

Move these files into `Modules/Sources/Authenticator`:

- `AuthenticatorModels.swift`
- `Base32.swift`
- `ProtoReader.swift`
- `TOTP.swift`
- `OtpAuthImport.swift`
- `AuthenticatorStore.swift`
- `AuthenticatorImportSheet.swift`
- `AuthenticatorSettingsView.swift`
- `AuthenticatorPanelView.swift`

Do not move `OnlySwitch/EverySwitch/AuthenticatorSwitch.swift`.

## Dependencies

The new target depends on:

- `Defines`, for layout constants used by the panel.
- `Extensions`, for localization and user defaults keys.
- `Utilities`, for `KeychainManager` and `LanguageManager`.

The app target depends on the new `Authenticator` product and imports it from:

- `OnlySwitch/EverySwitch/AuthenticatorSwitch.swift`
- `OnlySwitch/Features/OnlySwitchList/OnlySwitchListView.swift`
- `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`

## Public API

Types used outside the module must be public:

- `AuthenticatorStore`
- `AuthenticatorPanelView`
- `AuthenticatorSettingsView`
- `AuthenticatorAccount`
- `AuthenticatorAlgorithm`

Initializers and members required by the app or tests must also be public. Internal helper types can remain internal unless tests need direct access.

## Testing

Add focused Swift Testing coverage in `Modules/Tests/ModulesTests/AuthenticatorTests.swift` for core logic that can run without UI or keychain state:

- RFC 6238 SHA-1 TOTP code generation.
- `otpauth://totp/...` import parsing.
- Duplicate-free module access through public Authenticator types is checked by compiling the SwiftPM test target.

Do not test SwiftUI views directly.

## Verification

Run:

- `rtk swift test` from `Modules`
- An `xcodebuild` app build for the `OnlySwitch` scheme

The migration is complete when both commands compile with the app importing Authenticator from the package and no stale Authenticator source references remain in the app target.
