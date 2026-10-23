#if os(macOS)
import Foundation

/// Runtime IDs own group identity; labels never become cleanup targets.
public struct CleanerDeviceGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var items: [CleanerItem]
    public var runtimeIdentifier: String?

    public static func groups(items: [CleanerItem]) -> [Self] {
        let grouped = Dictionary(grouping: items.filter { $0.category == .simulatorDevice }) { item in
            item.runtimeIdentifier?.isEmpty == false ? item.runtimeIdentifier : nil
        }
        return grouped.map { identifier, devices in
            let names = devices.compactMap(\.runtimeName).filter { !$0.isEmpty }.sorted()
            return Self(id: identifier ?? "__unknown_os__", title: names.first ?? identifier ?? "Xcode Cleaner Unknown OS", items: devices.sorted(by: deviceOrder), runtimeIdentifier: identifier)
        }.sorted { lhs, rhs in
            if lhs.runtimeIdentifier == nil { return false }
            if rhs.runtimeIdentifier == nil { return true }
            let leftFamily = family(lhs), rightFamily = family(rhs)
            let familyOrder = compare(leftFamily, rightFamily)
            if familyOrder != .orderedSame { return familyOrder == .orderedAscending }
            let versionOrder = compare(version(lhs), version(rhs))
            if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
            return lhs.id < rhs.id
        }
    }
    private static func deviceOrder(_ lhs: CleanerItem, _ rhs: CleanerItem) -> Bool {
        let order = compare(lhs.title, rhs.title)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
    private static func family(_ group: Self) -> String {
        let source = group.title.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
        return String(source.prefix { !$0.isNumber }).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    private static func version(_ group: Self) -> String {
        guard let firstNumber = group.title.firstIndex(where: \.isNumber) else { return group.title }
        return String(group.title[firstNumber...].prefix { $0.isNumber || $0 == "." || $0 == "-" })
            .replacingOccurrences(of: "-", with: ".")
    }
    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
#endif
