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

    @Test func savesAndPostsChangeOnTheMainThread() async throws {
        let suite = "DesktopPetHungerSettingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let posted = LockIsolated<[Bool]>([])
        let token = center.addObserver(forName: .desktopPetNeedsSettingsChanged, object: nil, queue: nil) { _ in
            posted.withValue { $0.append(Thread.isMainThread) }
        }
        defer { center.removeObserver(token) }
        let setting = DesktopPetHungerSetting.userDefaults(defaults, notificationCenter: center)

        #expect(setting.load())
        await setting.save(false)
        #expect(!setting.load())
        #expect(posted.value == [true])
    }
}
