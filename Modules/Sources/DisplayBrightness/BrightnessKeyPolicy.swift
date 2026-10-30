import CoreGraphics

public struct BrightnessKeyTarget: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let isBuiltIn: Bool
    public let isAvailable: Bool
    public init(id: UInt32, frame: CGRect, isBuiltIn: Bool, isAvailable: Bool) {
        self.id = id; self.frame = frame; self.isBuiltIn = isBuiltIn; self.isAvailable = isAvailable
    }
}

public enum BrightnessKeyPolicy {
    public static func level(current: Double, key: BrightnessKeyEvent.Key, fine: Bool) -> Double {
        guard current.isFinite else { return 1 }
        let current = max(0, min(1, current))
        let step = 1.0 / (fine ? 64 : 16)
        // Hardware readback is quantized to whole percent. Half a percent counts as on the step.
        let slack = 0.005 / step
        switch key {
        case .increase: return min(1, ((current / step + slack).rounded(.down) + 1) * step)
        case .decrease: return max(0, ((current / step - slack).rounded(.up) - 1) * step)
        }
    }
    public static func authorizes(_ route: BrightnessKeyRoute, targets: [BrightnessKeyTarget],
                                  generation: UInt64, enabled: Bool = true, trusted: Bool = true) -> Bool {
        enabled && trusted && route.generation == generation && !route.ids.isEmpty
            && route.ids.allSatisfy { id in targets.contains { $0.id == id && !$0.isBuiltIn && $0.isAvailable } }
    }
    public static func targets(in displays: [BrightnessKeyTarget], pointer: CGPoint,
                               allExternal: Bool, enabled: Bool = true, trusted: Bool = true) -> [UInt32] {
        guard enabled, trusted else { return [] }
        if allExternal { return displays.filter { !$0.isBuiltIn && $0.isAvailable }.map(\.id) }
        // Screen order must not choose an arbitrary target in a malformed overlapping topology.
        let underPointer = displays.filter { $0.frame.contains(pointer) }
        guard underPointer.count == 1, let target = underPointer.first,
              !target.isBuiltIn, target.isAvailable else { return [] }
        return [target.id]
    }
}

public struct BrightnessKeyRoute: Equatable, Sendable {
    public let ids: [UInt32]
    public let generation: UInt64
    public init(ids: [UInt32], generation: UInt64) { self.ids = ids; self.generation = generation }
}

/// A key gesture keeps the decision made on its original down, including native pass-through.
public struct BrightnessKeyRoutingState: Sendable {
    private enum Gesture: Sendable { case native, suppressed, controlled(BrightnessKeyRoute) }
    private var held: [BrightnessKeyEvent.Key: Gesture] = [:]
    public init() {}
    public var hasCapturedGesture: Bool {
        held.values.contains { gesture in
            switch gesture { case .native: false; case .controlled, .suppressed: true }
        }
    }
    public mutating func reset() { held.removeAll() }
    public mutating func route(_ event: BrightnessKeyEvent, targets: [BrightnessKeyTarget], pointer: CGPoint,
                               generation: UInt64, enabled: Bool = true, trusted: Bool = true) -> BrightnessKeyRoute? {
        guard enabled, trusted else { reset(); return nil }
        if let gesture = held[event.key] {
            if !event.isKeyDown { held.removeValue(forKey: event.key) }
            switch gesture {
            case .native: return nil
            case .suppressed: return .init(ids: [], generation: generation)
            case let .controlled(route):
                guard route.generation == generation,
                      route.ids.allSatisfy({ id in targets.contains { $0.id == id && !$0.isBuiltIn && $0.isAvailable } }) else {
                    held[event.key] = event.isKeyDown ? .suppressed : nil
                    // Preserve a consumed gesture through topology-only invalidation; do not dispatch its stale targets.
                    return .init(ids: [], generation: generation)
                }
                return route
            }
        }
        // Neither an orphan release nor a repeat can start interception midway through a native gesture.
        guard event.isKeyDown, !event.isRepeat else { return nil }
        let ids = BrightnessKeyPolicy.targets(in: targets, pointer: pointer, allExternal: false)
        guard !ids.isEmpty else { held[event.key] = .native; return nil }
        let route = BrightnessKeyRoute(ids: ids, generation: generation)
        held[event.key] = .controlled(route)
        return route
    }
}
