import Foundation

/// Validated, persistent settings. Audio samples and process identifiers never enter this value.
public struct EqualizerSettings: Codable, Equatable, Sendable {
    public static let frequencies: [Double] = [31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    public static let flat = Self(gains: [])
    public private(set) var gains: [Double]
    public var isFlat: Bool { gains.allSatisfy { $0 == 0 } }

    public init(gains: [Double]) {
        self.gains = (0..<10).map { gains.indices.contains($0) ? Self.normalized(gains[$0]) : 0 }
    }

    public mutating func setGain(_ gain: Double, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = Self.normalized(gain)
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(12, max(-12, value)) : 0
    }

    private enum CodingKeys: String, CodingKey { case gains }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(gains: try values.decodeIfPresent([Double].self, forKey: .gains) ?? [])
    }
}
