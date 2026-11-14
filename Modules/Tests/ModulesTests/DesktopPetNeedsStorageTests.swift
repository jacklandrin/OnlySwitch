import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetNeedsStorageTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "DesktopPetNeedsStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func missingValuesReadAsNoNeedsAndHungerEnabled() throws {
        let storage = DesktopPetNeedsStorage.userDefaults(try makeDefaults())
        #expect(storage.loadNeeds() == nil)
        #expect(storage.isHungerEnabled())
    }

    @Test func savedNeedsLoadBack() throws {
        let storage = DesktopPetNeedsStorage.userDefaults(try makeDefaults())
        let needs = DesktopPetNeeds(lastFedAt: Date(timeIntervalSinceReferenceDate: 42))
        storage.saveNeeds(needs)
        #expect(storage.loadNeeds() == needs)
    }

    @Test func corruptNeedsReadAsNil() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("nope".utf8), forKey: DesktopPetNeedsStorage.needsKey)
        #expect(DesktopPetNeedsStorage.userDefaults(defaults).loadNeeds() == nil)
    }

    @Test func disabledHungerIsRead() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: DesktopPetNeedsStorage.hungerEnabledKey)
        #expect(!DesktopPetNeedsStorage.userDefaults(defaults).isHungerEnabled())
    }
}
