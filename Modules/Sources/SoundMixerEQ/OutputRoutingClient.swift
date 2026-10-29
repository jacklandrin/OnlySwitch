import Dependencies
import Foundation

public struct OutputRoutingClient: Sendable {
    public var load: @Sendable () -> [String: OutputRouteSelection]
    public var save: @Sendable (String, OutputRouteSelection) -> Void
    public var apply: @MainActor @Sendable (String, OutputRouteSelection) -> OutputRoutingFeature.Status
    public init(load: @escaping @Sendable () -> [String: OutputRouteSelection],
                save: @escaping @Sendable (String, OutputRouteSelection) -> Void,
                apply: @escaping @MainActor @Sendable (String, OutputRouteSelection) -> OutputRoutingFeature.Status) {
        self.load = load; self.save = save; self.apply = apply
    }
}

extension OutputRoutingClient: DependencyKey {
    public static let liveValue = Self(load: {
        guard let data = UserDefaults.standard.data(forKey: "soundMixerOutputRoutes"),
              let saved = try? JSONDecoder().decode([String: OutputRouteSelection].self, from: data) else { return [:] }
        return saved
    }, save: { id, selection in
        // Synchronous writes from the retained main-actor Store preserve edit ordering.
        let defaults = UserDefaults.standard
        var saved = defaults.data(forKey: "soundMixerOutputRoutes")
            .flatMap { try? JSONDecoder().decode([String: OutputRouteSelection].self, from: $0) } ?? [:]
        saved[id] = selection.followsSystem ? nil : selection
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerOutputRoutes") }
    }, apply: { _, _ in .unavailable })
    public static let testValue = Self(load: { [:] }, save: { _, _ in }, apply: { _, _ in .unavailable })
}

public extension DependencyValues {
    var outputRoutingClient: OutputRoutingClient {
        get { self[OutputRoutingClient.self] }
        set { self[OutputRoutingClient.self] = newValue }
    }
}
