import Foundation

public enum SystemMonitorFormatter {
    public static func rate(bytesPerSecond: Double) -> String {
        "\(bytes(bytes: bytesPerSecond))/s"
    }

    public static func bytes(bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(bytes, 0)
        var unitIndex = 0

        while value >= 1_024, unitIndex < units.count - 1 {
            value /= 1_024
            unitIndex += 1
        }

        let formattedValue: String
        if unitIndex == 0 || value >= 100 {
            formattedValue = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
        } else {
            formattedValue = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: ".0", with: "")
        }
        return "\(formattedValue) \(units[unitIndex])"
    }

    public static func percentage(_ value: Double) -> String {
        let percentage = min(max(value, 0), 1) * 100
        return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), percentage)
    }
}
