import CoreGraphics
import Testing
@testable import WebBrowser

struct BrowserToolbarRevealTests {
    @Test func hiddenToolbarRevealsOnlyFromTheTopStrip() {
        let hot = BrowserToolbarReveal.hotZoneHeight
        #expect(BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: 0, toolbarIsVisible: false, toolbarHeight: 90))
        #expect(BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: hot, toolbarIsVisible: false, toolbarHeight: 90))
        #expect(!BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: hot + 1, toolbarIsVisible: false, toolbarHeight: 90))
        #expect(!BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: nil, toolbarIsVisible: false, toolbarHeight: 90))
        #expect(!BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: -4, toolbarIsVisible: false, toolbarHeight: 90))
    }

    @Test func visibleToolbarStaysWhileThePointerIsOverIt() {
        let margin = BrowserToolbarReveal.visibleMargin
        #expect(BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: 90 + margin, toolbarIsVisible: true, toolbarHeight: 90))
        #expect(!BrowserToolbarReveal.pointerWantsToolbar(distanceFromTop: 91 + margin, toolbarIsVisible: true, toolbarHeight: 90))
        // Before the toolbar has been measured, the strip still applies.
        #expect(BrowserToolbarReveal.pointerWantsToolbar(
            distanceFromTop: BrowserToolbarReveal.hotZoneHeight, toolbarIsVisible: true, toolbarHeight: 0
        ))
    }

    @Test func editingInvalidInputAndVoiceOverPinTheToolbar() {
        #expect(!BrowserToolbarReveal.isPinned(addressFocused: false, showsInvalidAddress: false, voiceOverEnabled: false))
        #expect(BrowserToolbarReveal.isPinned(addressFocused: true, showsInvalidAddress: false, voiceOverEnabled: false))
        #expect(BrowserToolbarReveal.isPinned(addressFocused: false, showsInvalidAddress: true, voiceOverEnabled: false))
        #expect(BrowserToolbarReveal.isPinned(addressFocused: false, showsInvalidAddress: false, voiceOverEnabled: true))
    }

    @Test func revealWaitsBrieflyAndHidingWaitsLonger() {
        #expect(BrowserToolbarReveal.delay(revealing: true) < BrowserToolbarReveal.delay(revealing: false))
        #expect(BrowserToolbarReveal.delay(revealing: true) > .zero)
    }
}
