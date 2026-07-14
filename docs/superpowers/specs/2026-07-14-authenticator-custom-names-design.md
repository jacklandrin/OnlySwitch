# Authenticator Custom Names Design

## Goal

Allow users to assign a custom name to each Authenticator account so that accounts with similar imported issuer and account labels are easier to distinguish.

## User Experience

Each account row in **Settings > Authenticator** will expose a Rename action through both a pencil button and the row's context menu. Selecting Rename presents a small sheet containing a focused text field prefilled with the account's current custom name, or with the imported display label when no custom name has been set.

The sheet provides Cancel and Save actions. Save trims leading and trailing whitespace. A non-empty value becomes the account's custom name. An empty or whitespace-only value clears the custom name and restores the imported label.

The custom name replaces the imported label everywhere Authenticator accounts are displayed, including the Settings list and the expanded menu panel. Imported issuer and account values remain unchanged and continue to identify duplicate imports.

## Data Model

`AuthenticatorAccount` gains an optional `customName: String?` property. Existing persisted accounts do not contain this key, so synthesized `Codable` decoding must remain backward compatible by treating a missing key as `nil`. A focused custom decoder will preserve the existing stored account format while defaulting `customName` to `nil`.

`displayName` will return the trimmed custom name when it is non-empty. Otherwise it will preserve the current fallback behavior:

- account name when issuer is empty;
- issuer when account name is empty;
- `Issuer (account)` when both are present.

The imported issuer and account name remain the inputs to duplicate detection. Renaming therefore cannot cause a duplicate token to be re-imported.

## Store Behavior

`AuthenticatorStore` gains a rename operation that accepts an account identifier and a proposed custom name. It trims the value, stores `nil` for an empty result, updates only the matching account, and relies on the existing `accounts` persistence observer to write the updated array to `UserDefaults`.

If the account no longer exists when Save is selected, the operation is a no-op. Renaming never reads or changes the account secret in Keychain.

## View Structure

The rename sheet will be a small focused SwiftUI view owned by `AuthenticatorSettingsView`. The parent tracks the account being renamed and presents the sheet with item-based presentation so the selected account is explicit.

The row receives a rename closure instead of owning presentation state. Its pencil button and context-menu Rename command call the same closure. Existing copy and delete behavior remains unchanged.

## Error Handling

Renaming has no expected recoverable I/O error because persistence uses the existing `UserDefaults` path. A missing account is handled as a no-op. Empty input is a supported request to restore the imported label, not an error.

## Testing

Swift Testing coverage will verify:

- an account decoded from the legacy JSON shape receives no custom name;
- a non-empty custom name takes precedence over the imported label;
- leading and trailing whitespace is removed from the displayed custom name;
- an empty or whitespace-only custom name falls back to the imported label;
- the store's rename transformation updates only the selected account and converts empty input to `nil` through a testable model-level update API.

The Authenticator module test suite and the full project build will be run after implementation. The settings UI will also be checked for compilation and for consistency with the provided screenshot's existing layout.

## Scope

This feature does not add account reordering, editing of imported issuer/account metadata, bulk rename, cloud synchronization, or changes to TOTP generation and Keychain storage.
