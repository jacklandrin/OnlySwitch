import CoreGraphics

enum BrowserUserAgent {
    /// iPhone Safari, so sites serve their narrow layout in the menu-bar panel.
    static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

public enum BrowserLayout {
    /// Page height in the menu-bar popover, before clamping to the screen.
    public static let popoverContentHeight: CGFloat = 560
}
