import ComposableArchitecture
import Foundation
import Testing
@testable import DesktopPet

@MainActor
struct DesktopPetNeedsFeatureTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func firstStartCreatesFreshMealAndIsNotHungry() async {
        let saved = LockIsolated<[DesktopPetNeeds]>([])
        let start = start
        let store = TestStore(initialState: DesktopPetNeedsFeature.State()) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date.now = start
            $0.continuousClock = TestClock()
            $0.desktopPetNeedsStorage.loadNeeds = { nil }
            $0.desktopPetNeedsStorage.saveNeeds = { needs in saved.withValue { $0.append(needs) } }
            $0.desktopPetNeedsStorage.isHungerEnabled = { true }
        }

        await store.send(.start) {
            $0.needs = DesktopPetNeeds(lastFedAt: start)
            $0.isHungerEnabled = true
            $0.isHungry = false
        }
        await store.send(.stop)
        await store.finish()

        #expect(saved.value == [DesktopPetNeeds(lastFedAt: start)])
    }

    @Test func becomesHungryOnTickAfterInterval() async {
        let start = start
        let now = LockIsolated(start)
        let clock = TestClock()
        let store = TestStore(initialState: DesktopPetNeedsFeature.State()) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date = DateGenerator { now.value }
            $0.continuousClock = clock
            $0.desktopPetNeedsStorage.loadNeeds = { DesktopPetNeeds(lastFedAt: start) }
            $0.desktopPetNeedsStorage.isHungerEnabled = { true }
        }

        await store.send(.start) {
            $0.needs = DesktopPetNeeds(lastFedAt: start)
            $0.isHungerEnabled = true
        }
        now.setValue(start.addingTimeInterval(DesktopPetNeeds.hungerInterval))
        await clock.advance(by: DesktopPetNeedsFeature.checkInterval)
        await store.receive(\.tick) {
            $0.isHungry = true
        }
        await store.send(.stop)
    }

    @Test func feedingPlaysEatingThenEnds() async {
        let saved = LockIsolated<[DesktopPetNeeds]>([])
        let clock = TestClock()
        let fedAt = start.addingTimeInterval(DesktopPetNeeds.hungerInterval)
        var state = DesktopPetNeedsFeature.State()
        state.needs = DesktopPetNeeds(lastFedAt: start)
        state.isHungry = true
        let store = TestStore(initialState: state) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date.now = fedAt
            $0.continuousClock = clock
            $0.desktopPetNeedsStorage.saveNeeds = { needs in saved.withValue { $0.append(needs) } }
        }

        await store.send(.feedTapped) {
            $0.needs = DesktopPetNeeds(lastFedAt: fedAt)
            $0.isHungry = false
            $0.reaction = .eating
            $0.reactionStartedAt = fedAt
        }
        await clock.advance(by: DesktopPetNeedsFeature.reactionDuration)
        await store.receive(\.reactionFinished) {
            $0.reaction = nil
            $0.reactionStartedAt = nil
        }
        await store.finish()

        #expect(saved.value == [DesktopPetNeeds(lastFedAt: fedAt)])
    }

    @Test func feedingIsIgnoredWhenHungerDisabled() async {
        var state = DesktopPetNeedsFeature.State()
        state.isHungerEnabled = false
        let store = TestStore(initialState: state) { DesktopPetNeedsFeature() }
        await store.send(.feedTapped)
    }

    @Test func pettingReplacesEatingAndRestartsTimer() async {
        let start = start
        let clock = TestClock()
        var state = DesktopPetNeedsFeature.State()
        state.needs = DesktopPetNeeds(lastFedAt: start)
        let store = TestStore(initialState: state) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date.now = start
            $0.continuousClock = clock
            $0.desktopPetNeedsStorage.saveNeeds = { _ in }
        }

        await store.send(.feedTapped) {
            $0.reaction = .eating
            $0.reactionStartedAt = start
        }
        await clock.advance(by: .seconds(2))
        await store.send(.petTapped) {
            $0.reaction = .petted
        }
        // The eating timer (due at 3s) was cancelled; only the petting timer (due at 5s) may finish.
        await clock.advance(by: .seconds(2))
        await clock.advance(by: .seconds(1))
        await store.receive(\.reactionFinished) {
            $0.reaction = nil
            $0.reactionStartedAt = nil
        }
    }

    @Test func disablingHungerClearsHungryOnSettingsChange() async {
        var state = DesktopPetNeedsFeature.State()
        state.needs = DesktopPetNeeds(lastFedAt: start)
        state.isHungry = true
        let now = start.addingTimeInterval(DesktopPetNeeds.hungerInterval)
        let store = TestStore(initialState: state) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.desktopPetNeedsStorage.isHungerEnabled = { false }
        }

        await store.send(.settingsChanged) {
            $0.isHungerEnabled = false
            $0.isHungry = false
        }
    }

    @Test func futureMealIsNormalizedAndSavedOnStart() async {
        let saved = LockIsolated<[DesktopPetNeeds]>([])
        let start = start
        let store = TestStore(initialState: DesktopPetNeedsFeature.State()) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.date.now = start
            $0.continuousClock = TestClock()
            $0.desktopPetNeedsStorage.loadNeeds = { DesktopPetNeeds(lastFedAt: start.addingTimeInterval(9_999)) }
            $0.desktopPetNeedsStorage.saveNeeds = { needs in saved.withValue { $0.append(needs) } }
            $0.desktopPetNeedsStorage.isHungerEnabled = { true }
        }

        await store.send(.start) {
            $0.needs = DesktopPetNeeds(lastFedAt: start)
        }
        await store.send(.stop)
        await store.finish()

        #expect(saved.value == [DesktopPetNeeds(lastFedAt: start)])
    }
}
