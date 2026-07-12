# Only Control Secondary Information Design

## Goal

Show useful text information already available in one-column mode on the corresponding Only Control tile while keeping AirPods battery status beside the clock.

## Chosen Design

Each Only Control item may carry an optional subtitle. The subtitle appears below the item title in a smaller secondary style. Items without information retain their current visual layout and do not reserve an empty subtitle row.

The dashboard obtains subtitle text from the existing `SwitchBarVM.info` value, so one-column mode and Only Control remain consistent. Nonempty values, including the Only Agent model, are displayed as text with one-line truncation and scaling for long values.

AirPods battery information remains beside the clock as a glanceable system status and is not repeated on the AirPods tile.

## Alternatives Considered

1. Keep AirPods battery beside the clock and add only text subtitles to tiles. This is the selected approach because it preserves the richer battery display and gives text information a consistent home.
2. Add bespoke tile layouts for every switch. This allows richer visuals but introduces unnecessary per-switch UI and inconsistent behavior.
3. Use one optional subtitle model for every item, with compact AirPods formatting. This made the AirPods tile crowded and duplicated a status better suited to the header.

## Data Flow

When Only Control refreshes its dashboard, it refreshes each switch status and publishes the complete tile grid immediately. It then loads switch information in a follow-up effect and updates each tile subtitle progressively. A slow provider, such as the Xcode Derived Data size calculation, therefore cannot delay initial tile presentation. Existing single-item notifications continue to trigger a dashboard refresh, keeping changing information current when the switch reports an update.

AirPods information continues through the dedicated header battery state. Invalid or unavailable battery data hides that status rather than showing misleading percentages or placeholder UI.

## Layout and Accessibility

The icon, title, and optional subtitle form a centered vertical stack within the existing 85-point tile. Spacing and icon size may tighten slightly only when a subtitle exists. The subtitle uses the system secondary text color, distinct from the primary label in light, dark, active, and inactive tile states.

The complete item label and subtitle will be exposed together to VoiceOver. Long subtitle text remains available through the accessibility value even if visually truncated.

## Testing

- Verify `ControlItemViewState` equality and hashing include subtitle changes so SwiftUI refreshes the tile.
- Verify empty information maps to no subtitle.
- Verify regular information maps to localized display text.
- Verify AirPods information does not map to a tile subtitle.
- Build the macOS app and visually check tiles with no subtitle, Only Agent text, and the header AirPods battery view in light and dark appearance.

## Scope

This change affects Only Control presentation and its state construction only. It does not change switch-provider APIs, one-column mode, switch behavior, dashboard ordering, or tile sizing.
