# iOS Remote Dashboard Polish Design

## Goal

Fix three issues observed after pairing an iPhone with OnlySwitch:

1. Long Mac names consume multiple lines and are clipped on the dashboard.
2. The dashboard reports that the Mac was not found immediately after pairing.
3. Tile icons have inconsistent visual sizes.

The changes must preserve multiple-Mac selection, local-network reconnection, Dynamic Type, VoiceOver, and custom Mac display names.

## Root Causes

### Mac name layout

The dashboard uses a menu-style `Picker` whose selected value is rendered by the system. Long Bonjour service names can wrap inside the constrained 280-point area. The Mac app also derives its initial display name from `ProcessInfo.hostName`, which can resolve to a long network-provider hostname rather than the user-facing macOS Computer Name.

### Post-pairing connection

Bonjour browsing currently exists only while a discovery stream has a subscriber. Closing the pairing screen removes the final subscriber, cancels the browser, and clears the discovered endpoint candidates. If the newly paired session disconnects or reconnects, the selected Mac has no candidate endpoint and the runtime emits “Mac was not found on the local network.”

### Tile icon sizing

The tile reserves a 34-by-34-point slot, but SF Symbols are sized with a font while PNG icons are resizable and fill the slot. Their different sizing paths produce inconsistent visual bounds.

## Design

### Compact Mac selector

Replace the dashboard's menu-style `Picker` presentation with an explicit `Menu`. Its label will show the selected Mac on one line, truncate long names in the middle, and keep the disclosure indicator visible. The menu will list every paired Mac and mark the selected one. VoiceOver will continue to announce the full, untruncated selected name and selection state.

The selector remains capped at 280 points so it works on iPhone and does not become unnecessarily wide on iPad.

### Discovery lifetime

Treat Bonjour browsing as required when either:

- at least one discovery stream subscriber exists, or
- a paired Mac is selected.

Selecting a Mac will ensure browsing is active before reconnection begins. Removing the last discovery subscriber will stop browsing only when no Mac is selected. Clearing the selection or backgrounding the app will retain the existing cleanup behavior. Returning to the foreground will restart browsing for the selected Mac.

This keeps endpoint discovery current when DHCP, Wi-Fi, or network interfaces change. Persisting and reconstructing a previous endpoint is intentionally rejected because stale network endpoints are less reliable and require additional storage format changes.

### Human-friendly default Mac name

Use the macOS Computer Name as the default remote-access display name, falling back to the existing hostname and then “OnlySwitch Mac” if unavailable. Existing saved names and user-entered custom names will not be overwritten.

### Consistent tile icons

Render both SF Symbols and PNG resources as resizable, aspect-fit images inside the same 28-by-28-point visual frame. Keep the existing 34-by-34-point outer alignment slot so tile spacing and status accessories do not move.

## Error Handling and Lifecycle

Browser failures retain the existing bounded restart backoff. A selected Mac keeps discovery demand active across browser restarts. Backgrounding still cancels network work and clears transient candidates; foregrounding restores discovery before reconnecting.

If a Mac is genuinely absent, the existing retry sequence and offline message remain unchanged.

## Testing

Add regression coverage for:

- discovery demand with a selected Mac and no discovery subscribers;
- stopping discovery only when neither a subscriber nor a selected Mac needs it;
- selection starting discovery before reconnection;
- the preferred Computer Name and fallback name normalization;
- compact selector selection behavior where it can be tested at the feature boundary;
- the existing remote test target and physical-device build.

The final build will be installed on the connected iPhone for verification of discovery, the selector layout, reconnection after pairing, and icon sizing.

## Out of Scope

- Renaming an existing paired Mac automatically.
- Changing tile dimensions or dashboard column counts.
- Persisting raw Bonjour endpoints.
- Changing the pairing protocol or credentials.
