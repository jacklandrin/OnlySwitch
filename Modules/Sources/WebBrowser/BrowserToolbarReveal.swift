import CoreGraphics

/// When the auto-hiding browser toolbar is shown. It floats over the top of the page: resting the pointer on
/// the page's top strip reveals it, and it stays while the pointer is over it or the user is typing.
public enum BrowserToolbarReveal {
    /// Height of the strip at the top of the page that reveals the hidden toolbar.
    public static let hotZoneHeight: CGFloat = 28
    /// Extra room below a visible toolbar before the pointer counts as having left it.
    public static let visibleMargin: CGFloat = 8

    /// `distanceFromTop` is the pointer's distance from the page's top edge, or `nil` when it is outside the page.
    public static func pointerWantsToolbar(distanceFromTop: CGFloat?, toolbarIsVisible: Bool, toolbarHeight: CGFloat) -> Bool {
        guard let distanceFromTop, distanceFromTop >= 0 else { return false }
        let zone = toolbarIsVisible ? max(hotZoneHeight, toolbarHeight + visibleMargin) : hotZoneHeight
        return distanceFromTop <= zone
    }

    /// The toolbar stays visible regardless of the pointer while the user types an address, while an invalid
    /// address is flagged, and when VoiceOver is running (it cannot hover).
    public static func isPinned(addressFocused: Bool, showsInvalidAddress: Bool, voiceOverEnabled: Bool) -> Bool {
        addressFocused || showsInvalidAddress || voiceOverEnabled
    }

    /// A short dwell before revealing avoids flashing the toolbar when the pointer crosses the top edge on its
    /// way into the page; a longer one before hiding forgives small overshoots.
    public static func delay(revealing: Bool) -> Duration {
        revealing ? .milliseconds(180) : .milliseconds(700)
    }
}
