import Foundation

@MainActor
public enum AphroditeContentHeightReport {
    public static func parse(message: [String: Any], expectedNavigationToken: UUID, maximumHeight: CGFloat) -> CGFloat? {
        guard let token = message["token"] as? String, token == expectedNavigationToken.uuidString,
              maximumHeight.isFinite, maximumHeight >= 1 else { return nil }
        let height: CGFloat?
        if let number = message["height"] as? NSNumber { height = CGFloat(number.doubleValue) }
        else if let value = message["height"] as? Double { height = CGFloat(value) }
        else { height = nil }
        guard let height, height.isFinite, height >= 1, height <= maximumHeight else { return nil }
        return height
    }

    public static func shouldReport(previous: CGFloat?, next: CGFloat) -> Bool {
        guard next.isFinite else { return false }
        guard let previous else { return true }
        return abs(previous - next) >= 1
    }
}
