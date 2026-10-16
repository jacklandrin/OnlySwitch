import Foundation
import Testing
@testable import Extensions
@testable import Switches

struct SwitchLegacyIdentifierCompatibilityTests {
    @Test(arguments: [
        (SwitchType.hiddeDesktop, UInt64(1)),
        (SwitchType.emptyTrash, UInt64(16_384)),
        (SwitchType.reverseScrollDirection, UInt64(2_199_023_255_552)),
        (SwitchType.systemMonitor, UInt64(4_398_046_511_104)),
        (SwitchType.dockPreview, UInt64(17_592_186_044_416)),
    ])
    func legacyNumericIdentifiersRemainPubliclyStable(_ value: (SwitchType, UInt64)) {
        #expect(value.0.legacyIdentifier == value.1)
        #expect(SwitchType(legacyIdentifier: value.1) == value.0)
        #expect(String(value.0.legacyIdentifier) == String(value.1))
    }

    @Test("Dock Preview starts disabled independently of Customize visibility")
    func dockPreviewEnabledDefaultsOffAndIsIndependentOfVisibility() throws {
        let suite = "DockPreviewPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.object(forKey: UserDefaults.Key.dockPreviewEnabled) == nil)
        #expect(defaults.bool(forKey: UserDefaults.Key.dockPreviewEnabled) == false)
        #expect(SwitchVisibilityState.isVisible(.dockPreview, in: defaults) == false)

        defaults.set(true, forKey: UserDefaults.Key.dockPreviewEnabled)
        #expect(SwitchVisibilityState.isVisible(.dockPreview, in: defaults) == false)

        SwitchVisibilityState.setVisible(.dockPreview, for: true, in: defaults)
        #expect(defaults.bool(forKey: UserDefaults.Key.dockPreviewEnabled))
        SwitchVisibilityState.setVisible(.dockPreview, for: false, in: defaults)
        #expect(defaults.bool(forKey: UserDefaults.Key.dockPreviewEnabled))
    }

    @Test("Dock Preview enabled intent is included in settings backups")
    func dockPreviewPreferenceIsExportable() {
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.dockPreviewEnabled))
    }
}
