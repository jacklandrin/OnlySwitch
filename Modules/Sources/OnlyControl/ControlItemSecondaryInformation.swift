import Foundation

public enum ControlItemSecondaryInformation {
    public static func subtitle(info: String, isAirPods: Bool) -> String? {
        let trimmedInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInfo.isEmpty else {
            return nil
        }

        if isAirPods {
            return nil
        }
        return trimmedInfo
    }
}
