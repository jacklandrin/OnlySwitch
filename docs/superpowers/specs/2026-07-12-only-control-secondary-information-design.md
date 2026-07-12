# Only Control Secondary Information Design

## Goal

Show the useful secondary information already available in one-column mode on the corresponding Only Control tile. Examples include AirPods battery levels and the current Only Agent model.

## Chosen Design

Each Only Control item may carry an optional subtitle. The subtitle appears below the item title in a smaller secondary style. Items without information retain their current visual layout and do not reserve an empty subtitle row.

The dashboard obtains subtitle text from the existing `SwitchBarVM.info` value, so one-column mode and Only Control remain consistent. AirPods information is normalized into a concise battery summary suitable for the narrow tile. Other nonempty values, including the Only Agent model, are displayed as text with one-line truncation and scaling for long values.

AirPods battery information currently shown beside the clock will move onto the AirPods tile. This keeps status associated with the control it describes and avoids presenting the same information twice.

## Alternatives Considered

1. Keep AirPods battery beside the clock and add only text subtitles to tiles. This preserves the current header but does not satisfy the goal of showing AirPods information on its item.
2. Add bespoke tile layouts for every switch. This allows richer visuals but introduces unnecessary per-switch UI and inconsistent behavior.
3. Use one optional subtitle model for every item, with compact AirPods formatting. This is the selected approach because it is consistent, extensible, and small in scope.

## Data Flow

When Only Control refreshes its dashboard, it already refreshes each switch status. It will also refresh each switch's information and put the resulting optional subtitle into `ControlItemViewState`. The item view renders the subtitle when nonempty. Existing single-item notifications continue to trigger a dashboard refresh, keeping changing information current when the switch reports an update.

AirPods information uses the same provider value as one-column mode. Invalid or unavailable battery data produces no subtitle rather than misleading percentages or placeholder UI.

## Layout and Accessibility

The icon, title, and optional subtitle form a centered vertical stack within the existing 85-point tile. Spacing and icon size may tighten slightly only when a subtitle exists. The subtitle uses a secondary color that remains legible in light, dark, active, and inactive tile states.

The complete item label and subtitle will be exposed together to VoiceOver. Long subtitle text remains available through the accessibility value even if visually truncated.

## Testing

- Verify `ControlItemViewState` equality and hashing include subtitle changes so SwiftUI refreshes the tile.
- Verify empty information maps to no subtitle.
- Verify regular information maps to localized display text.
- Verify AirPods information maps to the compact battery summary and unavailable values are omitted.
- Build the macOS app and visually check tiles with no subtitle, Only Agent text, and AirPods battery text in light and dark appearance.

## Scope

This change affects Only Control presentation and its state construction only. It does not change switch-provider APIs, one-column mode, switch behavior, dashboard ordering, or tile sizing.
