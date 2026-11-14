import Foundation
import RemoteCore

/// A titled group of catalog controls shown in the target picker.
public struct ScheduleTargetGroup: Equatable, Identifiable {
    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case switches, buttons, evolution, shortcuts

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        public var titleKey: String {
            switch self {
            case .switches: "Schedule Section Switches"
            case .buttons: "Schedule Section Buttons"
            case .evolution: "Schedule Section Evolution"
            case .shortcuts: "Schedule Section Shortcuts"
            }
        }

        init(_ descriptor: RemoteControlDescriptor) {
            switch descriptor.id.kind {
            case .builtIn: self = descriptor.behavior == .button ? .buttons : .switches
            case .evolution: self = .evolution
            case .shortcut: self = .shortcuts
            }
        }
    }

    public var kind: Kind
    public var descriptors: [RemoteControlDescriptor]

    public var id: Kind { kind }
}

/// Groups and filters the catalog for the target picker.
public enum ScheduleTargetGroups {
    /// Non-empty groups in a fixed order (Switches, Buttons, Evolution, Shortcuts), each sorted by title.
    /// `search` matches titles ignoring case and diacritics; a blank search keeps everything.
    public static func make(catalog: [RemoteControlDescriptor], search: String) -> [ScheduleTargetGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? catalog : catalog.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return Dictionary(grouping: matching, by: ScheduleTargetGroup.Kind.init)
            .sorted { $0.key < $1.key }
            .map { kind, descriptors in
                ScheduleTargetGroup(kind: kind, descriptors: descriptors.sorted(by: titleOrder))
            }
    }

    private static func titleOrder(_ lhs: RemoteControlDescriptor, _ rhs: RemoteControlDescriptor) -> Bool {
        switch lhs.title.localizedStandardCompare(rhs.title) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.value < rhs.id.value
        }
    }
}
