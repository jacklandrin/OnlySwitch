import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetNeedsMotionTests {
    /// 0.6s past the reference date: outside the 0.13s blink window of the 5.4s blink cycle.
    let date = Date(timeIntervalSinceReferenceDate: 0.6)

    private func motion(
        at date: Date,
        hungry: Bool = false,
        reaction: DesktopPetReaction? = nil,
        startedAt: Date? = nil,
        working: Bool = false,
        music: Bool = false,
        reduceMotion: Bool = false
    ) -> MotionValues {
        DesktopPetMotion.values(
            at: date, pomodoroState: nil, isActive: true, isDragging: false,
            reduceMotion: reduceMotion, isMusicPlaying: music, isAgentWorking: working,
            isHungry: hungry, reaction: reaction, reactionStartedAt: startedAt
        )
    }

    @Test func reduceMotionKeepsReactionsStill() {
        #expect(motion(at: date, reaction: .petted, startedAt: date, reduceMotion: true) == .still)
    }

    @Test func eatingChompsOverTime() {
        let first = motion(at: date, reaction: .eating, startedAt: date)
        let second = motion(at: date.addingTimeInterval(0.1), reaction: .eating, startedAt: date)
        #expect(first.chomp != second.chomp)
        #expect((0...1).contains(first.chomp))
        #expect((0...1).contains(second.chomp))
    }

    @Test func reactionProgressGrowsAndClamps() {
        let start = motion(at: date, reaction: .eating, startedAt: date)
        let mid = motion(at: date.addingTimeInterval(1.5), reaction: .eating, startedAt: date)
        let late = motion(at: date.addingTimeInterval(10), reaction: .eating, startedAt: date)
        #expect(start.reactionProgress == 0)
        #expect(abs(mid.reactionProgress - 0.5) < 0.001)
        #expect(late.reactionProgress == 1)
    }

    @Test func pettingSwaysAndRaisesHearts() {
        let values = motion(at: date, reaction: .petted, startedAt: date.addingTimeInterval(-0.3))
        #expect(values.rotationDegrees != 0)
        #expect(values.heartRise > 0 && values.heartRise < 1)
    }

    @Test func reactionOverridesAgentWork() {
        let working = motion(at: date, working: true)
        let eating = motion(at: date, reaction: .eating, startedAt: date, working: true)
        #expect(eating != working)
        #expect(eating == motion(at: date, reaction: .eating, startedAt: date))
        #expect(eating.chomp > 0)
    }

    @Test func hungryDroopsEyesWhenNotBlinking() {
        let notBlinking = Date(timeIntervalSinceReferenceDate: 1.0)
        #expect(motion(at: notBlinking, hungry: true).eyeScale < 1)
        #expect(motion(at: notBlinking).eyeScale == 1)
    }

    @Test func musicOutranksHunger() {
        #expect(motion(at: date, hungry: true, music: true) == motion(at: date, music: true))
    }

    @Test func agentWorkOutranksHunger() {
        #expect(motion(at: date, hungry: true, working: true) == motion(at: date, working: true))
    }
}
