import Testing
@testable import DesktopPet

struct DesktopPetAnimationTests {
    @Test func contractRawValuesAreStable() {
        #expect(DesktopPetAnimation.allCases.map(\.rawValue) == [
            "idle", "focus", "break", "music", "working", "hungry", "eating", "petted", "dragging"
        ])
    }

    @Test(arguments: [
        (DesktopPetAnimationState(), DesktopPetAnimation.idle),
        (DesktopPetAnimationState(pomodoroPhase: .focus), .focus),
        (DesktopPetAnimationState(pomodoroPhase: .breakTime), .breakTime),
        (DesktopPetAnimationState(pomodoroPhase: .focus, isHungry: true), .hungry),
        (DesktopPetAnimationState(isMusicPlaying: true, isHungry: true), .music),
        (DesktopPetAnimationState(isMusicPlaying: true, isAgentWorking: true), .working),
        (DesktopPetAnimationState(isAgentWorking: true, reaction: .petted), .petted),
        (DesktopPetAnimationState(isHungry: true, reaction: .eating), .eating),
        (DesktopPetAnimationState(reaction: .eating, isDragging: true), .dragging),
    ])
    func resolvesByPriority(state: DesktopPetAnimationState, expected: DesktopPetAnimation) {
        #expect(state.animation == expected)
    }

    @Test func controlPresentationIsAModifierNotAState() {
        #expect(DesktopPetAnimationState(isControlPresented: true).animation == .idle)
    }

    @Test(arguments: [
        (DesktopPetAnimationState(isHungry: true), "Desktop pet hungry"),
        (DesktopPetAnimationState(isHungry: true, reaction: .eating), "Desktop pet eating"),
        (DesktopPetAnimationState(reaction: .petted), "Desktop pet enjoying pets"),
        (DesktopPetAnimationState(isAgentWorking: true, isHungry: true), "Desktop pet hungry"),
        (DesktopPetAnimationState(), nil),
    ] as [(DesktopPetAnimationState, String?)])
    func accessibilityStatusDescribesNeeds(state: DesktopPetAnimationState, key: String?) {
        #expect(state.accessibilityStatusKey == key)
    }
}
