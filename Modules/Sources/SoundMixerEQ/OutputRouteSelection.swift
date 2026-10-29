import Foundation

/// Desired routing, independent of which devices are connected right now.
public struct OutputRouteSelection: Codable, Equatable, Sendable {
    public private(set) var deviceUIDs: [String]
    public var followsSystem: Bool { deviceUIDs.isEmpty }
    public init(deviceUIDs: [String] = []) {
        self.deviceUIDs = Array(Set(deviceUIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).sorted().prefix(16))
    }
    public mutating func toggle(_ uid: String) {
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let index = deviceUIDs.firstIndex(of: uid) { deviceUIDs.remove(at: index) }
        else if deviceUIDs.count < 16 { deviceUIDs.append(uid); deviceUIDs.sort() }
    }
    private enum CodingKeys: String, CodingKey { case deviceUIDs }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(deviceUIDs: try container.decodeIfPresent([String].self, forKey: .deviceUIDs) ?? [])
    }
}

public struct OutputRouteDevice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isDefault: Bool
    public var channelCount: Int
    public init(id: String, name: String, isDefault: Bool, channelCount: Int) {
        self.id = id; self.name = name; self.isDefault = isDefault; self.channelCount = channelCount
    }
}

public struct OutputRouteResolution: Equatable, Sendable {
    public let onlineUIDs: [String]
    public let missingUIDs: [String]
    public let isWaiting: Bool
    public let requiresTap: Bool
    public init(selection: OutputRouteSelection, devices: [OutputRouteDevice]) {
        let available = Set(devices.filter { (1...64).contains($0.channelCount) }.map(\.id))
        if selection.followsSystem {
            onlineUIDs = devices.first(where: { $0.isDefault && available.contains($0.id) }).map { [$0.id] } ?? []
            missingUIDs = []; isWaiting = false; requiresTap = false
        } else {
            onlineUIDs = selection.deviceUIDs.filter { available.contains($0) }
            missingUIDs = selection.deviceUIDs.filter { !available.contains($0) }
            isWaiting = onlineUIDs.isEmpty
            requiresTap = !onlineUIDs.isEmpty
        }
    }
}
