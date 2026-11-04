import Testing
@testable import DisplayBrightness

struct BrightnessDimPolicyTests {
    @Test func dimsEveryDisplayByTheSamePercent() {
        let targets = BrightnessDimPolicy.targets(originals: [1: 1, 2: 0.8, 3: 0.5], percent: 0.5)
        #expect(targets == [1: 0.5, 2: 0.4, 3: 0.25])
    }

    @Test func clampsToTheMinimumInsteadOfGoingBlack() {
        let targets = BrightnessDimPolicy.targets(originals: [1: 0.15], percent: 0.5)
        #expect(targets == [1: BrightnessDimPolicy.minimumLevel])
    }

    @Test func skipsDisplaysAlreadyAtOrBelowTheMinimum() {
        let targets = BrightnessDimPolicy.targets(originals: [1: 1, 2: 0.1, 3: 0.05], percent: 0.5)
        #expect(targets == [1: 0.5])
    }

    @Test func returnsNothingWhenNoDisplayCanBeDimmed() {
        #expect(BrightnessDimPolicy.targets(originals: [1: 0.1], percent: 0.5).isEmpty)
        #expect(BrightnessDimPolicy.targets(originals: [:], percent: 0.5).isEmpty)
    }

    @Test func ignoresNonFiniteOrOutOfRangeInput() {
        #expect(BrightnessDimPolicy.targets(originals: [1: .nan], percent: 0.5).isEmpty)
        #expect(BrightnessDimPolicy.targets(originals: [1: 1], percent: .nan).isEmpty)
        #expect(BrightnessDimPolicy.targets(originals: [1: 1], percent: 2) == [1: 1])
    }
}
