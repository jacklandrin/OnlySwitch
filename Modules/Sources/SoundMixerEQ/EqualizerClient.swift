import Dependencies
import Foundation

public struct EqualizerClient: Sendable {
    public var load: @Sendable () -> [String: EqualizerSettings]
    public var save: @Sendable (String, EqualizerSettings) -> Void
    public var apply: @MainActor @Sendable (String, EqualizerSettings) -> EqualizerFeature.Status

    public init(load: @escaping @Sendable () -> [String: EqualizerSettings],
                save: @escaping @Sendable (String, EqualizerSettings) -> Void,
                apply: @escaping @MainActor @Sendable (String, EqualizerSettings) -> EqualizerFeature.Status) {
        self.load = load; self.save = save; self.apply = apply
    }
}

extension EqualizerClient: DependencyKey {
    public static let liveValue = Self(load: {
        guard let data = UserDefaults.standard.data(forKey: "soundMixerEqualizerSettings"),
              let saved = try? JSONDecoder().decode([String: EqualizerSettings].self, from: data) else { return [:] }
        return saved
    }, save: { id, settings in
        // The retained feature calls this synchronously on its main-actor store before audio effects.
        let defaults = UserDefaults.standard
        var saved = defaults.data(forKey: "soundMixerEqualizerSettings")
            .flatMap { try? JSONDecoder().decode([String: EqualizerSettings].self, from: $0) } ?? [:]
        saved[id] = settings.isFlat ? nil : settings
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerEqualizerSettings") }
    }, apply: { _, _ in .unavailable })
    public static let testValue = Self(load: { [:] }, save: { _, _ in }, apply: { _, _ in .unavailable })
}

public extension DependencyValues {
    var equalizerClient: EqualizerClient {
        get { self[EqualizerClient.self] }
        set { self[EqualizerClient.self] = newValue }
    }
}
