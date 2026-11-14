import CoreGraphics
import Testing
@testable import DesktopPet

struct DesktopPetEdgeDockingTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visibleFrame = CGRect(x: 0, y: 70, width: 1440, height: 805)

    @Test func docksAtTheLeftEdgeWhenPushedAgainstIt() {
        let frame = CGRect(x: 0, y: 300, width: 152, height: 160)

        #expect(
            DesktopPetEdgeDocking.dockEdge(
                for: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                screenFrames: [screenFrame]
            ) == .left
        )
    }

    @Test func docksAtTheRightEdgeWhenPushedAgainstIt() {
        let frame = CGRect(x: 1440 - 152, y: 300, width: 152, height: 160)

        #expect(
            DesktopPetEdgeDocking.dockEdge(
                for: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                screenFrames: [screenFrame]
            ) == .right
        )
    }

    @Test func staysUndockedAwayFromTheEdges() {
        let frame = CGRect(x: 8, y: 300, width: 152, height: 160)

        #expect(
            DesktopPetEdgeDocking.dockEdge(
                for: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                screenFrames: [screenFrame]
            ) == nil
        )
    }

    @Test func doesNotDockWhereAnotherDisplayContinuesPastTheEdge() {
        let frame = CGRect(x: 1440 - 152, y: 300, width: 152, height: 160)
        let externalScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        #expect(
            DesktopPetEdgeDocking.dockEdge(
                for: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                screenFrames: [screenFrame, externalScreen]
            ) == nil
        )
    }

    @Test func docksWhenTheNeighbouringDisplayDoesNotCoverThePet() {
        let frame = CGRect(x: 1440 - 152, y: 100, width: 152, height: 160)
        let raisedExternalScreen = CGRect(x: 1440, y: 600, width: 1920, height: 1080)

        #expect(
            DesktopPetEdgeDocking.dockEdge(
                for: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                screenFrames: [screenFrame, raisedExternalScreen]
            ) == .right
        )
    }

    @Test func hiddenFrameSitsJustBeyondTheScreenEdge() {
        let left = CGRect(x: 0, y: 300, width: 152, height: 160)
        let right = CGRect(x: 1288, y: 300, width: 152, height: 160)

        #expect(
            DesktopPetEdgeDocking.hiddenFrame(for: left, edge: .left, screenFrame: screenFrame)
                == CGRect(x: -152, y: 300, width: 152, height: 160)
        )
        #expect(
            DesktopPetEdgeDocking.hiddenFrame(for: right, edge: .right, screenFrame: screenFrame)
                == CGRect(x: 1440, y: 300, width: 152, height: 160)
        )
    }

    @Test func peekFrameLeavesOnlyTheHeadOnScreen() {
        let left = CGRect(x: 0, y: 300, width: 152, height: 160)
        let right = CGRect(x: 1288, y: 300, width: 152, height: 160)

        #expect(
            DesktopPetEdgeDocking.frame(for: .peeking, restingFrame: left, edge: .left, screenFrame: screenFrame)
                == CGRect(x: -80, y: 300, width: 152, height: 160)
        )
        #expect(
            DesktopPetEdgeDocking.frame(for: .peeking, restingFrame: right, edge: .right, screenFrame: screenFrame)
                == CGRect(x: 1368, y: 300, width: 152, height: 160)
        )
        #expect(
            DesktopPetEdgeDocking.frame(for: .revealed, restingFrame: right, edge: .right, screenFrame: screenFrame)
                == right
        )
    }

    @Test func peekingPetLeansOutOfTheEdge() {
        #expect(DesktopPetEdgeDocking.tilt(for: .peeking, edge: .left) > 0)
        #expect(DesktopPetEdgeDocking.tilt(for: .peeking, edge: .right) < 0)
        #expect(DesktopPetEdgeDocking.tilt(for: .revealed, edge: .right) == 0)
        #expect(DesktopPetEdgeDocking.tilt(for: .hidden, edge: .left) == 0)
    }

    @Test func approachingTheEdgePeeksAndTouchingItPopsOut() {
        let resting = CGRect(x: 1288, y: 300, width: 152, height: 160)

        func phase(_ point: CGPoint, from current: DesktopPetEdgePhase) -> DesktopPetEdgePhase {
            DesktopPetEdgeDocking.phase(
                forMouseLocation: point,
                restingFrame: resting,
                edge: .right,
                screenFrame: screenFrame,
                current: current
            )
        }

        #expect(phase(CGPoint(x: 800, y: 380), from: .hidden) == .hidden)
        #expect(phase(CGPoint(x: 1380, y: 380), from: .hidden) == .peeking)
        #expect(phase(CGPoint(x: 1380, y: 600), from: .hidden) == .hidden)
        #expect(phase(CGPoint(x: 1439, y: 380), from: .peeking) == .revealed)
        #expect(phase(CGPoint(x: 1439, y: 600), from: .hidden) == .hidden)
    }

    @Test func revealedPetStaysUntilTheMouseLeavesIt() {
        let resting = CGRect(x: 0, y: 300, width: 152, height: 160)

        func phase(_ point: CGPoint) -> DesktopPetEdgePhase {
            DesktopPetEdgeDocking.phase(
                forMouseLocation: point,
                restingFrame: resting,
                edge: .left,
                screenFrame: screenFrame,
                current: .revealed
            )
        }

        #expect(phase(CGPoint(x: 120, y: 380)) == .revealed)
        #expect(phase(CGPoint(x: 0, y: 380)) == .revealed)
        #expect(phase(CGPoint(x: 400, y: 380)) == .hidden)
    }

    @Test func popSpringOvershootsThenSettlesOnTarget() {
        var spring = DesktopPetSpring(
            position: CGPoint(x: 1368, y: 300),
            target: CGPoint(x: 1288, y: 300),
            motion: .pop(edge: .right)
        )
        var minX = spring.position.x
        var maxY = spring.position.y
        for _ in 0..<240 where !spring.isSettled {
            spring.step(by: 1.0 / 120.0)
            minX = min(minX, spring.position.x)
            maxY = max(maxY, spring.position.y)
        }

        #expect(minX < 1288)
        #expect(maxY > 300)
        #expect(spring.isSettled)
        #expect(spring.position == CGPoint(x: 1288, y: 300))
    }

    @Test func hideSpringWindsUpBeforeDuckingBehindTheEdge() {
        var spring = DesktopPetSpring(
            position: CGPoint(x: 1288, y: 300),
            target: CGPoint(x: 1440, y: 300),
            motion: .hide(edge: .right)
        )
        spring.step(by: 1.0 / 120.0)
        #expect(spring.position.x < 1288)

        for _ in 0..<240 where !spring.isSettled {
            spring.step(by: 1.0 / 120.0)
        }
        #expect(spring.isSettled)
        #expect(spring.position == CGPoint(x: 1440, y: 300))
    }

    @Test(arguments: [
        DesktopPetMinimumPhaseCase(control: false, completion: false, reaction: false, hungry: false, expected: .hidden),
        DesktopPetMinimumPhaseCase(control: false, completion: false, reaction: false, hungry: true, expected: .peeking),
        DesktopPetMinimumPhaseCase(control: false, completion: false, reaction: true, hungry: true, expected: .revealed),
        DesktopPetMinimumPhaseCase(control: false, completion: false, reaction: true, hungry: false, expected: .revealed),
        DesktopPetMinimumPhaseCase(control: true, completion: false, reaction: false, hungry: false, expected: .revealed),
        DesktopPetMinimumPhaseCase(control: false, completion: true, reaction: false, hungry: false, expected: .revealed),
    ])
    func minimumPhaseKeepsNeedsVisible(_ testCase: DesktopPetMinimumPhaseCase) {
        #expect(DesktopPetEdgeDocking.minimumPhase(
            isControlPresented: testCase.control,
            hasCompletion: testCase.completion,
            hasReaction: testCase.reaction,
            isHungry: testCase.hungry
        ) == testCase.expected)
    }

    @Test func phasesAreOrderedByVisibility() {
        #expect(DesktopPetEdgePhase.hidden.visibility < DesktopPetEdgePhase.peeking.visibility)
        #expect(DesktopPetEdgePhase.peeking.visibility < DesktopPetEdgePhase.revealed.visibility)
    }
}

struct DesktopPetMinimumPhaseCase: Sendable, CustomTestStringConvertible {
    let control: Bool
    let completion: Bool
    let reaction: Bool
    let hungry: Bool
    let expected: DesktopPetEdgePhase

    var testDescription: String {
        "control=\(control) completion=\(completion) reaction=\(reaction) hungry=\(hungry) -> \(expected)"
    }
}
