import CoreGraphics
import Testing
@testable import DisplayBrightness

struct BrightnessKeyRoutingTests {
    let targets = [BrightnessKeyTarget(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), isBuiltIn: true, isAvailable: true),
                   BrightnessKeyTarget(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), isBuiltIn: false, isAvailable: true)]
    @Test func controlledGestureKeepsTargetUntilKeyUp() {
        var state = BrightnessKeyRoutingState()
        let down = BrightnessKeyEvent(key: .increase, isKeyDown: true)
        let up = BrightnessKeyEvent(key: .increase, isKeyDown: false)
        let first = state.route(down, targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 1)
        let repeated = state.route(.init(key: .increase, isKeyDown: true, isRepeat: true), targets: targets, pointer: CGPoint(x: 50, y: 50), generation: 1)
        let released = state.route(up, targets: targets, pointer: CGPoint(x: 50, y: 50), generation: 1)
        #expect(first?.ids == [2]); #expect(repeated == first); #expect(released == first)
        #expect(state.route(up, targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 1) == nil)
    }
    @Test func nativeGestureIsNotStolenAfterPointerMoves() {
        var state = BrightnessKeyRoutingState()
        let first = state.route(.init(key: .decrease, isKeyDown: true), targets: targets, pointer: CGPoint(x: 50, y: 50), generation: 1)
        let repeated = state.route(.init(key: .decrease, isKeyDown: true, isRepeat: true), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 1)
        let released = state.route(.init(key: .decrease, isKeyDown: false), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 1)
        #expect(first == nil); #expect(repeated == nil); #expect(released == nil)
    }
    @Test func topologyInvalidationSuppressesHeldGestureAndPermissionRevocationFailsOpen() {
        var state = BrightnessKeyRoutingState()
        _ = state.route(.init(key: .increase, isKeyDown: true), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 1)
        #expect(state.hasCapturedGesture)
        let invalid = state.route(.init(key: .increase, isKeyDown: true, isRepeat: true), targets: [], pointer: CGPoint(x: 150, y: 50), generation: 2)
        #expect(invalid?.ids == [])
        #expect(state.hasCapturedGesture)
        let released = state.route(.init(key: .increase, isKeyDown: false), targets: [], pointer: CGPoint(x: 150, y: 50), generation: 2)
        #expect(released?.ids == [])
        #expect(state.hasCapturedGesture == false)
        let orphan = state.route(.init(key: .increase, isKeyDown: true, isRepeat: true), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 2)
        #expect(orphan == nil)
        _ = state.route(.init(key: .decrease, isKeyDown: true), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 2)
        let revoked = state.route(.init(key: .decrease, isKeyDown: false), targets: targets, pointer: CGPoint(x: 150, y: 50), generation: 2, trusted: false)
        #expect(revoked == nil)
    }
    @Test func queuedCallbackRequiresCurrentTopologyPermissionAndTargets() {
        let route = BrightnessKeyRoute(ids: [2], generation: 1)
        #expect(BrightnessKeyPolicy.authorizes(route, targets: targets, generation: 1))
        #expect(BrightnessKeyPolicy.authorizes(route, targets: targets, generation: 2) == false)
        #expect(BrightnessKeyPolicy.authorizes(route, targets: targets, generation: 1, enabled: false) == false)
        #expect(BrightnessKeyPolicy.authorizes(route, targets: targets, generation: 1, trusted: false) == false)
        #expect(BrightnessKeyPolicy.authorizes(route, targets: [], generation: 1) == false)
        #expect(BrightnessKeyPolicy.authorizes(.init(ids: [1], generation: 1), targets: targets, generation: 1) == false)
    }

}
