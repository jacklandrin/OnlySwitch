import Foundation
import Testing
@testable import Extensions
@testable import Switches

struct SwitchVisibilityStateTests {
    private let historicalDefaultTypes: Set<SwitchType> = [
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
        .xcodeCache,
        .hiddenFiles,
        .radioStation,
    ]

    private var buttonTypes: Set<SwitchType> {
        Set(SwitchType.allCases.filter { $0.barInfo().controlType == .Button })
    }

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

    @Test func migratesLegacyStringMaskToStableNames() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("10", forKey: UserDefaults.Key.SwitchState)

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode, .mute])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode", "mute"])
    }

    @Test func legacyNSNumberAndUInt64MasksRetainEverySelectedButton() {
        let selectedTypes = buttonTypes.union([.darkMode])
        let mask = selectedTypes.reduce(UInt64.zero) { $0 | $1.legacyIdentifier }

        for value: Any in [NSNumber(value: mask), mask] {
            let (defaults, suite) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(value, forKey: UserDefaults.Key.SwitchState)

            #expect(SwitchVisibilityState.visibleTypes(from: defaults) == selectedTypes)
            #expect(
                defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]
                    == canonicalIdentifiers(for: selectedTypes)
            )
        }
    }

    @Test func canonicalizesNewFormatAndRetainsEverySelectedButton() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let selectedTypes = buttonTypes.union([.darkMode])
        defaults.set(
            selectedTypes.map(\.rawValue) + ["unknown", "darkMode"],
            forKey: UserDefaults.Key.SwitchState
        )

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == selectedTypes)
        #expect(
            defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]
                == canonicalIdentifiers(for: selectedTypes)
        )
    }

    @Test func buttonVisibilityMutationsArePersisted() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["darkMode"], forKey: UserDefaults.Key.SwitchState)

        for type in buttonTypes {
            SwitchVisibilityState.setVisible(type, for: true, in: defaults)
        }

        let selectedTypes = buttonTypes.union([.darkMode])
        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == selectedTypes)
        #expect(
            defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]
                == canonicalIdentifiers(for: selectedTypes)
        )

        for type in buttonTypes {
            SwitchVisibilityState.setVisible(type, for: false, in: defaults)
        }

        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode])
        #expect(defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String] == ["darkMode"])
    }

    @Test func persistsVisibilityMutations() {
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

    @Test func malformedExistingValueDoesNotReplaceSelectionWithHistoricalDefaults() {
        let malformed = makeDefaults()
        defer { malformed.defaults.removePersistentDomain(forName: malformed.suite) }
        malformed.defaults.set("not-a-mask", forKey: UserDefaults.Key.SwitchState)

        #expect(SwitchVisibilityState.load(from: malformed.defaults) == .unreadable)
        #expect(SwitchVisibilityState.visibleTypes(from: malformed.defaults).isEmpty)
        #expect(malformed.defaults.string(forKey: UserDefaults.Key.SwitchState) == "not-a-mask")
    }

    @Test func missingValueUsesHistoricalDefaults() {
        let missing = makeDefaults()
        defer { missing.defaults.removePersistentDomain(forName: missing.suite) }

        #expect(
            SwitchVisibilityState.load(from: missing.defaults)
                == .missing(historicalDefaultTypes)
        )
        #expect(
            missing.defaults.array(forKey: UserDefaults.Key.SwitchState) as? [String]
                == canonicalIdentifiers(for: historicalDefaultTypes)
        )
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

        #expect(visibleTypes == historicalDefaultTypes)
        #expect(visibleTypes.contains(.codexUsage) == false)
        #expect(visibleTypes.contains(.reverseScrollDirection) == false)
    }

    private func canonicalIdentifiers(for types: Set<SwitchType>) -> [String] {
        types
            .sorted { $0.legacyIdentifier < $1.legacyIdentifier }
            .map(\.rawValue)
    }
}
