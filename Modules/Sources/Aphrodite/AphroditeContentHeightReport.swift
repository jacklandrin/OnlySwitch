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

@MainActor
public enum AphroditeContentSizeReport {
    public static func parse(message: [String: Any], expectedNavigationToken: UUID, maximumDimension: CGFloat) -> CGSize? {
        guard let token = message["token"] as? String, token == expectedNavigationToken.uuidString,
              maximumDimension.isFinite, maximumDimension >= 1,
              let width = number(message["width"]), let height = number(message["height"]),
              width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= maximumDimension, height <= maximumDimension else { return nil }
        return CGSize(width: width, height: height)
    }

    public static func shouldReport(previous: CGSize?, next: CGSize) -> Bool {
        guard next.width.isFinite, next.height.isFinite else { return false }
        guard let previous else { return true }
        return abs(previous.width - next.width) >= 1 || abs(previous.height - next.height) >= 1
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let value = value as? Double { return CGFloat(value) }
        return nil
    }
}
