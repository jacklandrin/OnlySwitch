import Extensions
import Foundation
import Testing
@testable import AppFeature

@MainActor
struct SettingsNewBadgeTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "SettingsNewBadgeTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func desktopPetIsAnnouncedAsNew() {
        #expect(SettingsItem.newItems.contains(.DesktopPet))
    }

    @Test func onlyUnseenNewItemsShowTheBadge() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = SettingsNewBadgeTracker(defaults: defaults, newItems: [.DesktopPet])

        let seen = tracker.seenItems()

        #expect(seen.isEmpty)
        #expect(tracker.showsBadge(for: .DesktopPet, seen: seen))
        #expect(!tracker.showsBadge(for: .General, seen: seen))
    }

    @Test func markingSeenHidesTheBadgeForGood() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = SettingsNewBadgeTracker(defaults: defaults, newItems: [.DesktopPet])

        let seen = tracker.markSeen(.DesktopPet)

        #expect(seen == [.DesktopPet])
        #expect(!tracker.showsBadge(for: .DesktopPet, seen: seen))
        let relaunched = SettingsNewBadgeTracker(defaults: defaults, newItems: [.DesktopPet])
        #expect(!relaunched.showsBadge(for: .DesktopPet, seen: relaunched.seenItems()))
    }

    @Test func markingAnItemThatIsNotNewStoresNothing() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = SettingsNewBadgeTracker(defaults: defaults, newItems: [.DesktopPet])

        let seen = tracker.markSeen(.General)

        #expect(seen.isEmpty)
        #expect(defaults.object(forKey: UserDefaults.Key.seenNewSettingsItems) == nil)
    }

    @Test func unknownStoredValuesAreIgnored() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["Removed Page", SettingsItem.DesktopPet.rawValue], forKey: UserDefaults.Key.seenNewSettingsItems)
        let tracker = SettingsNewBadgeTracker(defaults: defaults, newItems: [.DesktopPet])

        #expect(tracker.seenItems() == [.DesktopPet])
    }

    @Test func badgeStateIsNotPartOfSettingsBackup() {
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.seenNewSettingsItems))
    }
}
