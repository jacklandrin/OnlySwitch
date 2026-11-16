import Foundation
import Testing
@testable import Extensions

/// Issue #232: the external display DDC gate reads an isolated defaults suite here.
struct ExternalDisplayDDCGateTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ExternalDisplayDDCGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func gateDefaultsToDisabledWhenUnset() throws {
        try withDefaults { defaults in
            #expect(defaults.object(forKey: UserDefaults.Key.externalDisplayDDCEnabled) == nil)
            #expect(!UserDefaults.isExternalDisplayDDCEnabled(in: defaults))
        }
    }

    @Test(arguments: [false, true])
    func gateHonorsStoredValue(_ stored: Bool) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: UserDefaults.Key.externalDisplayDDCEnabled)
            #expect(UserDefaults.isExternalDisplayDDCEnabled(in: defaults) == stored)
        }
    }

    @Test func gateFallsBackToDisabledWhenStoredValueIsNotABool() throws {
        try withDefaults { defaults in
            defaults.set("on", forKey: UserDefaults.Key.externalDisplayDDCEnabled)
            #expect(!UserDefaults.isExternalDisplayDDCEnabled(in: defaults))
        }
    }

    @Test func masterGateDefaultsToEnabledWhenUnset() throws {
        try withDefaults { defaults in
            #expect(UserDefaults.isDisplayBrightnessEnabled(in: defaults))
        }
    }

    @Test(arguments: [false, true])
    func masterGateHonorsStoredValue(_ stored: Bool) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: UserDefaults.Key.displayBrightnessEnabled)
            #expect(UserDefaults.isDisplayBrightnessEnabled(in: defaults) == stored)
        }
    }

    @Test func masterGateFallsBackToEnabledWhenStoredValueIsNotABool() throws {
        try withDefaults { defaults in
            defaults.set("off", forKey: UserDefaults.Key.displayBrightnessEnabled)
            #expect(UserDefaults.isDisplayBrightnessEnabled(in: defaults))
        }
    }

    @Test func masterKeyIsStable() {
        #expect(UserDefaults.Key.displayBrightnessEnabled == "displayBrightnessEnabledKey")
    }

    @Test func gateKeyIsStableAndDistinctFromTabVisibility() {
        #expect(UserDefaults.Key.externalDisplayDDCEnabled == "externalDisplayDDCEnabledKey")
        #expect(UserDefaults.Key.externalDisplayDDCEnabled != UserDefaults.Key.showBrightnessTab)
    }
}
