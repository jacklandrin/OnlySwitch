import Foundation

public enum ControlItemSecondaryInformation {
    public static func subtitle(info: String, isAirPods: Bool) -> String? {
        let trimmedInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInfo.isEmpty else {
            return nil
        }

        guard isAirPods else {
            return trimmedInfo
        }

        let labels = ["C", "L", "R"]
        let values = trimmedInfo
            .split { character in
                !character.isNumber && character != "-"
            }
            .compactMap { Int($0) }

        let batteries = zip(labels, values).compactMap { label, value -> String? in
            guard (0...100).contains(value) else {
                return nil
            }
            return "\(label) \(value)%"
        }

        return batteries.isEmpty ? nil : batteries.joined(separator: " · ")
    }
}
