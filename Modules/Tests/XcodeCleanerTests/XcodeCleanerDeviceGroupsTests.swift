#if os(macOS)
import Foundation
import Testing
@testable import XcodeCleaner

struct XcodeCleanerDeviceGroupsTests {
    private func device(_ id: String, _ title: String, runtime: String?, name: String?, detail: String = "", status: String? = nil) -> CleanerItem {
        .init(id: id, category: .simulatorDevice, title: title, bytes: nil, detail: detail, statusKey: status, runtimeIdentifier: runtime, runtimeName: name)
    }

    @Test func devicesSharingRuntimeFormOneGroupWithOriginalDeletionIDs() throws {
        let items = [device("device:b", "Phone B", runtime: "ios27", name: "iOS 27.1"), device("device:a", "Phone A", runtime: "ios27", name: "iOS 27.1")]
        let groups = CleanerDeviceGroup.groups(items: items)
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.id == "ios27")
        #expect(group.title == "iOS 27.1")
        #expect(group.items.map(\.id) == ["device:a", "device:b"])
    }

    @Test func familiesSortAlphabeticallyAndVersionsSortNumericallyDescending() {
        let items = [
            device("watch", "Watch", runtime: "watch27", name: "watchOS 27.1"),
            device("old", "Phone", runtime: "ios18", name: "iOS 18.6"),
            device("minor2", "Phone", runtime: "ios27-2", name: "iOS 27.2"),
            device("minor10", "Phone", runtime: "ios27-10", name: "iOS 27.10")
        ]
        #expect(CleanerDeviceGroup.groups(items: items).map(\.title) == ["iOS 27.10", "iOS 27.2", "iOS 18.6", "watchOS 27.1"])
    }

    @Test func missingDescriptorAndKnownDescriptorVersionsShareNumericOrdering() {
        let raw = "com.apple.CoreSimulator.SimRuntime.iOS-28-1"
        let items = [device("old", "Phone", runtime: "ios27", name: "iOS 27.1"), device("new", "Phone", runtime: raw, name: nil)]
        #expect(CleanerDeviceGroup.groups(items: items).map(\.title) == [raw, "iOS 27.1"])
    }

    @Test func differentRuntimeIdentitiesWithSameDisplayNameStaySeparate() {
        let items = [device("a", "Phone", runtime: "ios27-buildA", name: "iOS 27.1"), device("b", "Phone", runtime: "ios27-buildB", name: "iOS 27.1")]
        #expect(Set(CleanerDeviceGroup.groups(items: items).map(\.id)) == ["ios27-buildA", "ios27-buildB"])
    }

    @Test func deviceNamesTieBreakByStableIDAndIgnoreInputOrder() {
        let items = [device("z", "Same", runtime: "ios", name: "iOS 27"), device("b", "Alpha", runtime: "ios", name: "iOS 27"), device("a", "Same", runtime: "ios", name: "iOS 27")]
        #expect(CleanerDeviceGroup.groups(items: items).first?.items.map(\.id) == ["b", "a", "z"])
        #expect(CleanerDeviceGroup.groups(items: Array(items.reversed())) == CleanerDeviceGroup.groups(items: items))
    }

    @Test func missingDescriptorUsesIdentifierAndMissingIdentitySortsLast() throws {
        let rawRuntime = "com.apple.CoreSimulator.SimRuntime.iOS-28-1"
        let groups = CleanerDeviceGroup.groups(items: [
            device("unknown", "Mystery", runtime: nil, name: nil, detail: "iOS 99.9"),
            device("raw", "Phone", runtime: rawRuntime, name: nil)
        ])
        #expect(groups.count == 2)
        #expect(groups.first?.title == rawRuntime)
        #expect(groups.last?.title == "Xcode Cleaner Unknown OS")
        #expect(groups.last?.items.map(\.id) == ["unknown"])
        #expect(groups.allSatisfy { $0.title != "iOS 99.9" })
    }

    @Test func unavailableDevicesRemainGroupedAndOtherCategoriesAreExcluded() {
        let unavailable = device("missing", "Old Phone", runtime: "ios18", name: "iOS 18.6", status: "Unavailable")
        let cache = CleanerItem(id: "cache", category: .derivedData, title: "Cache", bytes: 1)
        let groups = CleanerDeviceGroup.groups(items: [cache, unavailable])
        #expect(groups.flatMap(\.items) == [unavailable])
        #expect(CleanerDeviceGroup.groups(items: []).isEmpty)
    }
}
#endif
