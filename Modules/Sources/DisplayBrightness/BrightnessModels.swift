import Foundation

public struct BrightnessSettings: Equatable, Sendable {
    public var smoothTransitions: Bool
    public var combinedDimming: Bool
    public var syncNativeBrightness: Bool
    public var allowZeroSoftwareBrightness: Bool
    public var controlWithBrightnessKeys: Bool
    public init(smoothTransitions: Bool = true, combinedDimming: Bool = true,
                syncNativeBrightness: Bool = false, allowZeroSoftwareBrightness: Bool = false,
                controlWithBrightnessKeys: Bool = true) {
        self.smoothTransitions = smoothTransitions
        self.combinedDimming = combinedDimming
        self.syncNativeBrightness = syncNativeBrightness
        self.allowZeroSoftwareBrightness = allowZeroSoftwareBrightness
        self.controlWithBrightnessKeys = controlWithBrightnessKeys
    }
}

public enum BrightnessControl: Equatable, Sendable { case native, ddc, software, unavailable }

public struct BrightnessOutput: Equatable, Sendable {
    public var hardware: Double?
    public var software: Double
    public init(hardware: Double?, software: Double) { self.hardware = hardware; self.software = software }
}

public struct BrightnessDisplay: Equatable, Identifiable, Sendable {
    public var id: UInt32
    public var name: String
    public var control: BrightnessControl
    public var level: Double
    public var appliedLevel: Double
    public var error: Bool
    /// An internal intent replaced this already accepted slider revision.
    public var supersededUIRevision: UInt64
    public init(id: UInt32, name: String, control: BrightnessControl, level: Double,
                appliedLevel: Double? = nil, error: Bool = false, supersededUIRevision: UInt64 = 0) {
        self.id = id; self.name = name; self.control = control; self.level = level
        self.appliedLevel = appliedLevel ?? level; self.error = error
        self.supersededUIRevision = supersededUIRevision
    }
}

public enum BrightnessKeyStatus: Equatable, Sendable {
    case inactive, ready, needsAccessibility, unavailable
}

public struct BrightnessSnapshot: Equatable, Sendable {
    public var generation: UInt64
    public var displays: [BrightnessDisplay]
    public var brightnessKeyStatus: BrightnessKeyStatus
    public init(generation: UInt64 = 0, displays: [BrightnessDisplay] = [],
                brightnessKeyStatus: BrightnessKeyStatus = .inactive) {
        self.generation = generation; self.displays = displays
        self.brightnessKeyStatus = brightnessKeyStatus
    }
}

public struct BrightnessRequest: Equatable, Sendable {
    public var screenID: UInt32
    public var generation: UInt64
    public var level: Double
    public var revision: UInt64
    public init(screenID: UInt32, generation: UInt64, level: Double, revision: UInt64) {
        self.screenID = screenID; self.generation = generation; self.level = level; self.revision = revision
    }
}

public enum BrightnessError: Error, Equatable, Sendable { case unavailable, staleRequest, writeFailed, invalidLevel }
