import Foundation
import Testing
@testable import Extensions
@testable import Switches

struct SwitchVisibilityStateTests {
    private let historicalDefaultPersistentTypes: Set<SwitchType> = [
        .hiddeDesktop,
        .darkMode,
        .topNotch,
        .mute,
        .keepAwake,
        .screenSaver,
        .nightShift,
        .autohideDock,
        .autohideMenuBar,
        .airPods,
        .bluetooth,
        .hiddenFiles,
        .radioStation,
    ]

    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "SwitchVisibilityStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test(arguments: [
        (SwitchType.hiddeDesktop, UInt64(1)),
        (SwitchType.darkMode, UInt64(2)),
        (SwitchType.reverseScrollDirection, UInt64(2_199_023_255_552)),
    ])
    func legacyIdentifiersRemainDecodable(_ value: (SwitchType, UInt64)) {
        #expect(value.0.legacyIdentifier == value.1)
        #expect(SwitchType(legacyIdentifier: value.1) == value.0)
    }

    @Test func buttonsDoNotPersistVisibility() {
        #expect(SwitchType.emptyTrash.persistsVisibility == false)
        #expect(SwitchType.darkMode.persistsVisibility)
    }

    @Test func migratesLegacyMaskToStableNames() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("10", forKey: UserDefaults.Key.SwitchState)

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode, .mute])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode", "mute"])
    }

    @Test func canonicalizesNewFormatAndIgnoresUnknownValues() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            ["mute", "unknown", "darkMode", "darkMode", "emptyTrash"],
            forKey: UserDefaults.Key.SwitchState
        )

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode, .mute])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode", "mute"])
    }

    @Test func ignoresButtonVisibilityMutations() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["darkMode"], forKey: UserDefaults.Key.SwitchState)

        SwitchVisibilityState.setVisible(.emptyTrash, for: true, in: defaults)

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode"])
    }

    @Test func persistsMutationsForPersistentTypesOnly() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["darkMode"], forKey: UserDefaults.Key.SwitchState)

        SwitchVisibilityState.setVisible(.mute, for: true, in: defaults)
        #expect(SwitchVisibilityState.isVisible(.mute, in: defaults))
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode", "mute"])

        SwitchVisibilityState.setVisible(.darkMode, for: false, in: defaults)
        #expect(SwitchVisibilityState.isVisible(.darkMode, in: defaults) == false)
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["mute"])
    }

    @Test func malformedOrMissingLegacyValueUsesHistoricalPersistentDefaults() {
        let malformed = makeDefaults()
        defer { malformed.defaults.removePersistentDomain(forName: malformed.suite) }
        malformed.defaults.set("not-a-mask", forKey: UserDefaults.Key.SwitchState)

        #expect(SwitchVisibilityState.visibleTypes(from: malformed.defaults) == historicalDefaultPersistentTypes)

        let missing = makeDefaults()
        defer { missing.defaults.removePersistentDomain(forName: missing.suite) }
        #expect(SwitchVisibilityState.visibleTypes(from: missing.defaults) == historicalDefaultPersistentTypes)
    }

    @Test func unknownLegacyBitsAreIgnored() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(String((UInt64(1) << 63) | 2), forKey: UserDefaults.Key.SwitchState)

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode"])
    }

    @Test func emptyNewFormatRemainsIntentionallyEmptyAndRepeatedReadsAreIdempotent() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([String](), forKey: UserDefaults.Key.SwitchState)

        let firstRead = SwitchVisibilityState.visibleTypes(from: defaults)
        let firstStorage = defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]
        let secondRead = SwitchVisibilityState.visibleTypes(from: defaults)
        let secondStorage = defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]

        #expect(firstRead.isEmpty)
        #expect(secondRead.isEmpty)
        #expect(firstStorage == [])
        #expect(secondStorage == firstStorage)
    }

    @Test func historicalDefaultDoesNotRestorePreviouslyHiddenDiscoveredSwitches() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UserDefaults.Key.didInstallCodexUsageSwitch)
        defaults.set(true, forKey: UserDefaults.Key.didInstallReverseScrollDirectionSwitch)

        let visibleTypes = SwitchVisibilityState.visibleTypes(from: defaults)

        #expect(visibleTypes == historicalDefaultPersistentTypes)
        #expect(visibleTypes.contains(.codexUsage) == false)
        #expect(visibleTypes.contains(.reverseScrollDirection) == false)
    }
}
