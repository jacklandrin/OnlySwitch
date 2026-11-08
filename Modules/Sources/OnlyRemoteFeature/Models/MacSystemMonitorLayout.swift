import Foundation
import RemoteCore

struct MacSystemMonitorLayout: Codable, Equatable, Sendable {
    let macID: UUID
    var visibleMetrics: Set<SystemMonitorMetric>
    var order: [SystemMonitorMetric]

    init(
        macID: UUID,
        visibleMetrics: Set<SystemMonitorMetric>,
        order: [SystemMonitorMetric]
    ) {
        self.macID = macID
        self.visibleMetrics = visibleMetrics.intersection(Set(SystemMonitorMetric.allCases))
        self.order = Self.normalizedOrder(order)
    }

    static func `default`(macID: UUID) -> Self {
        Self(
            macID: macID,
            visibleMetrics: Set(SystemMonitorMetric.allCases),
            order: SystemMonitorMetric.allCases
        )
    }

    var orderedVisibleMetrics: [SystemMonitorMetric] {
        order.filter(visibleMetrics.contains)
    }

    mutating func setVisible(_ metric: SystemMonitorMetric, isVisible: Bool) {
        if isVisible {
            visibleMetrics.insert(metric)
        } else {
            visibleMetrics.remove(metric)
        }
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        let validSource = source.filter(order.indices.contains)
        guard validSource.isEmpty == false else { return }
        let moved = validSource.map { order[$0] }
        for index in validSource.sorted(by: >) {
            order.remove(at: index)
        }
        let adjustedDestination = max(
            0,
            min(destination - validSource.filter { $0 < destination }.count, order.count)
        )
        order.insert(contentsOf: moved, at: adjustedDestination)
    }

    private enum CodingKeys: String, CodingKey {
        case macID
        case visibleMetrics
        case order
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        macID = try container.decode(UUID.self, forKey: .macID)
        let visibleRaw = try container.decodeIfPresent([String].self, forKey: .visibleMetrics)
        let orderRaw = try container.decodeIfPresent([String].self, forKey: .order)
        visibleMetrics = Set(
            (visibleRaw ?? SystemMonitorMetric.allCases.map(\.rawValue))
                .compactMap(SystemMonitorMetric.init(rawValue:))
        )
        order = Self.normalizedOrder(
            (orderRaw ?? []).compactMap(SystemMonitorMetric.init(rawValue:))
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(macID, forKey: .macID)
        try container.encode(visibleMetrics.map(\.rawValue).sorted(), forKey: .visibleMetrics)
        try container.encode(order.map(\.rawValue), forKey: .order)
    }

    private static func normalizedOrder(_ proposed: [SystemMonitorMetric]) -> [SystemMonitorMetric] {
        var seen = Set<SystemMonitorMetric>()
        let known = proposed.filter { seen.insert($0).inserted }
        return known + SystemMonitorMetric.allCases.filter { seen.insert($0).inserted }
    }
}
