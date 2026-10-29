import Foundation

/// Picks the display whose DDC channel belongs to an audio output device.
public enum DDCDisplayMatcher {
    /// Matches the EDID product name to the audio device name; with a single external display the
    /// names may differ (e.g. "DisplayPort Audio"). Never guesses between several candidates.
    public static func index(forAudioDeviceNamed audioName: String, displayNames: [String?]) -> Int? {
        let target = normalized(audioName)
        let matches = displayNames.indices.filter { displayNames[$0].map(normalized) == target }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty, displayNames.count == 1 { return 0 }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
