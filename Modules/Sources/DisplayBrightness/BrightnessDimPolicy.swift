/// Dim Screen scales every display's brightness by one shared percent.
public enum BrightnessDimPolicy {
    /// Below this the screen becomes hard to read, so dimming never goes lower.
    public static let minimumLevel = 0.1

    /// Displays already at or below the minimum are left alone; an empty result means nothing can be dimmed.
    public static func targets(originals: [UInt32: Double], percent: Double) -> [UInt32: Double] {
        guard percent.isFinite else { return [:] }
        let percent = max(0, min(1, percent))
        return originals.reduce(into: [:]) { targets, entry in
            let (id, original) = entry
            guard original.isFinite, original > minimumLevel else { return }
            targets[id] = max(minimumLevel, min(1, original) * percent)
        }
    }
}
