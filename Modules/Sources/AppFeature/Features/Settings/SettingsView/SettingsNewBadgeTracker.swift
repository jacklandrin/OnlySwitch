import Extensions
import Foundation

/// Remembers which newly added Settings pages the user has opened, so their "New" badge shows only until then.
/// Badge state is per-device UI state and deliberately not part of settings backups.
struct SettingsNewBadgeTracker {
    private let defaults: UserDefaults
    private let newItems: Set<SettingsItem>
    private let key = UserDefaults.Key.seenNewSettingsItems

    init(defaults: UserDefaults = .standard, newItems: Set<SettingsItem> = SettingsItem.newItems) {
        self.defaults = defaults
        self.newItems = newItems
    }

    /// Seen items, ignoring stored values for pages that no longer exist.
    func seenItems() -> Set<SettingsItem> {
        let stored = defaults.stringArray(forKey: key) ?? []
        return Set(stored.compactMap(SettingsItem.init(rawValue:)))
    }

    func showsBadge(for item: SettingsItem, seen: Set<SettingsItem>) -> Bool {
        newItems.contains(item) && !seen.contains(item)
    }

    /// Records that the user opened `item` and returns the updated seen set. Items that are not new are not stored.
    @discardableResult
    func markSeen(_ item: SettingsItem) -> Set<SettingsItem> {
        var seen = seenItems()
        guard newItems.contains(item), !seen.contains(item) else { return seen }
        seen.insert(item)
        defaults.set(seen.map(\.rawValue).sorted(), forKey: key)
        return seen
    }
}
