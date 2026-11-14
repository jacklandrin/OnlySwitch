import Dependencies
import Defines
import DesktopPet
import Extensions
import Foundation
import Testing
@testable import AppFeature

struct DesktopPetHungerSettingTests {
    @Test func keysMatchThePetModule() {
        #expect(UserDefaults.Key.desktopPetHungerEnabled == DesktopPetNeedsStorage.hungerEnabledKey)
        #expect(UserDefaults.Key.desktopPetNeeds == DesktopPetNeedsStorage.needsKey)
    }

    @Test func onlyTheSettingIsBackedUp() {
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.desktopPetHungerEnabled))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.desktopPetNeeds))
    }

    @Test func savesAndPostsChange() throws {
        let suite = "DesktopPetHungerSettingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let posted = LockIsolated(0)
        let token = center.addObserver(forName: .desktopPetNeedsSettingsChanged, object: nil, queue: nil) { _ in
            posted.withValue { $0 += 1 }
        }
        defer { center.removeObserver(token) }
        let setting = DesktopPetHungerSetting.userDefaults(defaults, notificationCenter: center)

        #expect(setting.load())
        setting.save(false)
        #expect(!setting.load())
        #expect(posted.value == 1)
    }
}
