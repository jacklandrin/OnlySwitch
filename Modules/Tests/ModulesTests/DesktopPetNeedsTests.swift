import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetNeedsTests {
    let fedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func notHungryJustBeforeInterval() {
        let needs = DesktopPetNeeds(lastFedAt: fedAt)
        #expect(!needs.isHungry(at: fedAt.addingTimeInterval(DesktopPetNeeds.hungerInterval - 1)))
    }

    @Test func hungryAtInterval() {
        let needs = DesktopPetNeeds(lastFedAt: fedAt)
        #expect(needs.isHungry(at: fedAt.addingTimeInterval(DesktopPetNeeds.hungerInterval)))
    }

    @Test func hungerIntervalIsFourHours() {
        #expect(DesktopPetNeeds.hungerInterval == 4 * 60 * 60)
    }

    @Test func futureMealIsClampedToNow() {
        let now = fedAt
        let needs = DesktopPetNeeds(lastFedAt: now.addingTimeInterval(86_400))
        #expect(!needs.isHungry(at: now))
        #expect(needs.normalized(at: now) == DesktopPetNeeds(lastFedAt: now))
    }

    @Test func pastMealIsUnchangedByNormalization() {
        let needs = DesktopPetNeeds(lastFedAt: fedAt)
        #expect(needs.normalized(at: fedAt.addingTimeInterval(10)) == needs)
    }

    @Test func feedingResetsHunger() {
        var needs = DesktopPetNeeds(lastFedAt: fedAt)
        let later = fedAt.addingTimeInterval(DesktopPetNeeds.hungerInterval * 2)
        needs.feed(at: later)
        #expect(!needs.isHungry(at: later))
        #expect(needs.lastFedAt == later)
    }

    @Test func roundTripsThroughJSON() throws {
        let needs = DesktopPetNeeds(lastFedAt: fedAt)
        let decoded = try JSONDecoder().decode(DesktopPetNeeds.self, from: JSONEncoder().encode(needs))
        #expect(decoded == needs)
    }
}
