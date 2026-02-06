---
name: onlyswitch-deeplink
description: Invoke OnlySwitch built-in switches or buttons via deeplink. Use when the user asks to toggle or trigger an OnlySwitch action (e.g. empty trash, keep awake, dark mode, mute, hide desktop, clear clipboard, eject discs, Xcode derived data, and any other built-in switch or button). Resolve the request to the correct switch id and open the onlyswitch deeplink.
metadata: {"openclaw":{"os":["darwin"],"homepage":"https://github.com/jacklandrin/OnlySwitch"}}
---

# OnlySwitch Deeplink

Invoke OnlySwitch built-in switches or one-shot buttons by opening its deeplink. OnlySwitch must be installed and allowed to handle the `onlyswitch://` URL scheme.

## Workflow

1. **Resolve intent to switch id**  
   Map the user's request to a single built-in switch/button using [references/switch-ids.md](references/switch-ids.md). Match phrases like "empty trash", "toggle keep awake", "mute mic", "clear xcode cache" to the correct **id** (e.g. empty trash → 16384, keep awake → 16).

2. **Open the deeplink**  
   Run on the user's machine (macOS):

   ```bash
   open "onlyswitch://run?type=builtIn&id=<id>"
   ```

   Replace `<id>` with the numeric id from the reference table. Example for "empty trash":

   ```bash
   open "onlyswitch://run?type=builtIn&id=16384"
   ```

3. **Confirm**  
   Tell the user which action was triggered (e.g. "Emptied trash via OnlySwitch" or "Toggled Keep Awake via OnlySwitch").

## Notes

- One deeplink per request: resolve to exactly one switch id per user message.
- If the request doesn't match any built-in (e.g. custom switch or unknown action), say that OnlySwitch deeplinks only support the built-in list and suggest checking the app or docs.
- IDs are raw enum values from `SwitchType` in the OnlySwitch app (see project's `SwitchType.swift` for the source of truth; this skill's reference table is derived from it).
