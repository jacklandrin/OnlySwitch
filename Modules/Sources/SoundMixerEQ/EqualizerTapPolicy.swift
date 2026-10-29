public enum EqualizerTapPolicy {
    public static func requiresTap(gain: Double, settings: EqualizerSettings, hasExplicitRoute: Bool = false) -> Bool {
        gain < 1 || !settings.isFlat || hasExplicitRoute
    }

    public static func requiresRebuild(previousProcessIDs: [UInt32], previousOutputUID: String,
                                       processIDs: [UInt32], outputUID: String) -> Bool {
        Set(previousProcessIDs) != Set(processIDs) || previousOutputUID != outputUID
    }
}
