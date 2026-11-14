import DesktopPetSkinKit
import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetSkinDocumentTests {
    @MainActor @Test func skinRendersOnlyWhileThePetIsShown() {
        let presentation = DesktopPetPresentation()
        presentation.skin = DesktopPetSkin(
            id: UUID(), name: "Cat", summary: "", createdAt: .distantPast, contractVersion: 1, markup: ""
        )
        #expect(presentation.renderedSkin == nil)
        presentation.isShown = true
        #expect(presentation.renderedSkin == presentation.skin)
    }

    @Test func attributesReflectState() {
        let state = DesktopPetAnimationState(pomodoroPhase: .breakTime, isHungry: true, isControlPresented: true)
        let values = Dictionary(uniqueKeysWithValues: DesktopPetSkinAttributes.values(
            for: state, reduceMotion: true, isPaused: false
        ).map { ($0.name, $0.value) })
        #expect(values == [
            "data-state": "hungry", "data-control": "on", "data-pomodoro": "break",
            "data-hungry": "true", "data-reduce-motion": "true", "data-paused": "false",
        ])
    }

    @Test func attributesDefaultToCalmValues() {
        let values = Dictionary(uniqueKeysWithValues: DesktopPetSkinAttributes.values(
            for: DesktopPetAnimationState(), reduceMotion: false, isPaused: false
        ).map { ($0.name, $0.value) })
        #expect(values == [
            "data-state": "idle", "data-control": "off", "data-pomodoro": "none",
            "data-hungry": "false", "data-reduce-motion": "false", "data-paused": "false",
        ])
    }

    @Test func scriptOnlySetsWhitelistedAttributes() {
        let script = DesktopPetSkinAttributes.script(
            DesktopPetSkinAttributes.values(for: DesktopPetAnimationState(), reduceMotion: false, isPaused: true)
        )
        #expect(script.contains("document.documentElement.setAttribute(\"data-state\",\"idle\")"))
        #expect(script.contains("\"data-paused\",\"true\""))
        #expect(!script.contains("eval"))
    }

    @Test func documentEmbedsCSPAndInitialAttributes() {
        let html = DesktopPetSkinDocument.make(
            markup: "<div id=\"pet\"></div>",
            attributes: DesktopPetSkinAttributes.values(for: DesktopPetAnimationState(), reduceMotion: false, isPaused: false)
        )
        #expect(html.contains("script-src 'none'"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("data-state=\"idle\""))
        #expect(html.contains("<div id=\"pet\"></div>"))
        #expect(html.contains("animation-play-state: paused"))
    }

    @Test(arguments: DesktopPetAnimation.allCases)
    func previewStateResolvesToRequestedAnimation(animation: DesktopPetAnimation) {
        #expect(DesktopPetAnimationState.preview(animation).animation == animation)
    }
}
