import Testing
@testable import DisplayBrightness

struct BrightnessKeyAccumulatorTests {
    @Test func queuedRepeatsAccumulateBeforeTheFirstHardwareWriteCompletes() {
        var accumulator = BrightnessKeyAccumulator()
        let first = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        let second = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        let third = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        #expect([first.level, second.level, third.level] == [0.5625, 0.625, 0.6875])
        #expect(first.revision < second.revision)
        #expect(second.revision < third.revision)
    }

    @Test func completionOfAnOlderWriteCannotDiscardTheNewestPendingLevel() {
        var accumulator = BrightnessKeyAccumulator()
        let first = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        let second = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        accumulator.finish(screenID: 1, revision: first.revision)
        let reversed = accumulator.next(screenID: 1, current: 0.5, key: .decrease, fine: false)
        #expect(reversed.level == 0.5625)
        accumulator.finish(screenID: 1, revision: second.revision)
        let continued = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        #expect(continued.level == 0.625)
    }

    @Test func completedLatestOrCancelledIntentUsesFreshObservedBrightness() {
        var accumulator = BrightnessKeyAccumulator()
        let first = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        accumulator.finish(screenID: 1, revision: first.revision)
        let observed = accumulator.next(screenID: 1, current: 0.75, key: .decrease, fine: false)
        #expect(observed.level == 0.6875)
        accumulator.cancel(screenID: 1)
        let slider = accumulator.next(screenID: 1, current: 0.25, key: .increase, fine: false)
        #expect(slider.level == 0.3125)
        #expect(slider.revision > observed.revision)
    }

    @Test func displaysAccumulateIndependentlyAndResetCannotReuseAnOldRevision() {
        var accumulator = BrightnessKeyAccumulator()
        let first = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        let other = accumulator.next(screenID: 2, current: 0.25, key: .decrease, fine: true)
        #expect(other.level == 0.234375)
        let next = accumulator.next(screenID: 1, current: 0.5, key: .increase, fine: false)
        #expect(next.level == 0.625)
        accumulator.reset()
        let replacement = accumulator.next(screenID: 1, current: 0.75, key: .decrease, fine: false)
        #expect(replacement.level == 0.6875)
        #expect(replacement.revision > next.revision)
        accumulator.finish(screenID: 1, revision: first.revision)
        let followup = accumulator.next(screenID: 1, current: 0.75, key: .decrease, fine: false)
        #expect(followup.level == 0.625)
    }
}
