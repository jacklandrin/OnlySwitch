import CoreGraphics

/// Logical webpage dimensions in points, independent of the display's pixel density.
public enum BrowserViewportSize: String, Codable, CaseIterable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    public var size: CGSize {
        switch self {
        case .compact: CGSize(width: 320, height: 568)
        case .standard: CGSize(width: 375, height: 667)
        case .large: CGSize(width: 390, height: 844)
        case .extraLarge: CGSize(width: 430, height: 932)
        }
    }

    public var label: String { "\(Int(size.width)) × \(Int(size.height))" }
}
