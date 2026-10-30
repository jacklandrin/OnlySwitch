import CoreGraphics
import Testing
@testable import DisplayBrightness

struct BrightnessKeyEventTests {
    @Test(arguments: [(2, BrightnessKeyEvent.Key.increase), (3, .decrease)])
    func decodesBrightnessKeys(code: Int, key: BrightnessKeyEvent.Key) {
        let event = BrightnessKeyEvent(subtype: 8, data1: encoded(code, state: 0x0A))
        #expect(event?.key == key)
        #expect(event?.isKeyDown == true)
        #expect(event?.isRepeat == false)
    }

    @Test func decodesKeyUpAndRepeatedKeyDown() {
        let up = BrightnessKeyEvent(subtype: 8, data1: encoded(2, state: 0x0B))
        #expect(up?.key == .increase)
        #expect(up?.isKeyDown == false)
        let repeated = BrightnessKeyEvent(subtype: 8, data1: encoded(3, state: 0x0A, repeated: true))
        #expect(repeated?.key == .decrease)
        #expect(repeated?.isKeyDown == true)
        #expect(repeated?.isRepeat == true)
    }

    @Test(arguments: [
        (Int16(7), Int(0x00020A00)), // other system event subtype
        (Int16(8), Int(0x00000A00)), // volume up
        (Int16(8), Int(0x00010A00)), // volume down
        (Int16(8), Int(0x00070A00)), // mute
        (Int16(8), Int(0x00100A00)), // play/pause
        (Int16(8), Int(0x00150A00)), // keyboard illumination up
        (Int16(8), Int(0x00160A00)), // keyboard illumination down
        (Int16(8), Int(0x00170A00)), // keyboard illumination toggle
        (Int16(8), Int(0x00020500)), // unknown key state
    ])
    func rejectsUnrelatedOrMalformedEvents(subtype: Int16, data1: Int) {
        #expect(BrightnessKeyEvent(subtype: subtype, data1: data1) == nil)
    }

    private func encoded(_ key: Int, state: Int, repeated: Bool = false) -> Int {
        key << 16 | state << 8 | (repeated ? 1 : 0)
    }
}

struct BrightnessKeyPolicyTests {
    @Test(arguments: [(0.0, 0.0625), (0.5, 0.5625), (0.96, 1.0), (1.0, 1.0)])
    func increaseMovesToNextSixteenth(current: Double, expected: Double) {
        #expect(BrightnessKeyPolicy.level(current: current, key: .increase, fine: false) == expected)
    }

    @Test(arguments: [(0.0, 0.0), (0.5, 0.4375), (1.0, 0.9375)])
    func decreaseMovesToPreviousSixteenth(current: Double, expected: Double) {
        #expect(BrightnessKeyPolicy.level(current: current, key: .decrease, fine: false) == expected)
    }

    @Test func shiftOptionUsesSixtyFourths() {
        #expect(BrightnessKeyPolicy.level(current: 0.5, key: .increase, fine: true) == 0.515625)
        #expect(BrightnessKeyPolicy.level(current: 0.5, key: .decrease, fine: true) == 0.484375)
    }

    @Test func roundedHardwareReadbackDoesNotStallTheNextStep() {
        var level = 0.0
        for _ in 0..<16 {
            let target = BrightnessKeyPolicy.level(current: level, key: .increase, fine: false)
            level = (target * 100).rounded() / 100
        }
        #expect(level == 1)
        for _ in 0..<16 {
            let target = BrightnessKeyPolicy.level(current: level, key: .decrease, fine: false)
            level = (target * 100).rounded() / 100
        }
        #expect(level == 0)
    }

    @Test func malformedLevelsCannotProduceUnsafeOrNonfiniteTargets() {
        #expect(BrightnessKeyPolicy.level(current: .nan, key: .decrease, fine: false) == 1)
        #expect(BrightnessKeyPolicy.level(current: .infinity, key: .increase, fine: true) == 1)
        #expect(BrightnessKeyPolicy.level(current: -3, key: .decrease, fine: false) == 0)
        #expect(BrightnessKeyPolicy.level(current: 3, key: .increase, fine: false) == 1)
    }

    @Test func pointerRoutingSelectsOnlyAvailableExternalScreenInQuartzCoordinates() {
        let screens = targets()
        #expect(BrightnessKeyPolicy.targets(in: screens, pointer: CGPoint(x: 1600, y: 200), allExternal: false) == [2])
        #expect(BrightnessKeyPolicy.targets(in: screens, pointer: CGPoint(x: -500, y: -300), allExternal: false) == [3])
        #expect(BrightnessKeyPolicy.targets(in: screens, pointer: CGPoint(x: 500, y: 200), allExternal: false).isEmpty)
        #expect(BrightnessKeyPolicy.targets(in: screens, pointer: CGPoint(x: 3100, y: 200), allExternal: false).isEmpty)
        #expect(BrightnessKeyPolicy.targets(in: screens, pointer: CGPoint(x: 9000, y: 9000), allExternal: false).isEmpty)
    }

    @Test func allExternalRoutingExcludesBuiltInAndUnavailableDisplays() {
        #expect(BrightnessKeyPolicy.targets(in: targets(), pointer: CGPoint(x: 500, y: 200), allExternal: true) == [2, 3])
        #expect(BrightnessKeyPolicy.targets(in: [], pointer: .zero, allExternal: true).isEmpty)
    }

    @Test func disabledOrUntrustedInterceptionAlwaysPassesThrough() {
        let pointer = CGPoint(x: 1600, y: 200)
        #expect(BrightnessKeyPolicy.targets(in: targets(), pointer: pointer, allExternal: false, enabled: false, trusted: true).isEmpty)
        #expect(BrightnessKeyPolicy.targets(in: targets(), pointer: pointer, allExternal: true, enabled: true, trusted: false).isEmpty)
    }

    private func targets() -> [BrightnessKeyTarget] {
        [
            .init(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isBuiltIn: true, isAvailable: true),
            .init(id: 2, frame: CGRect(x: 1440, y: 0, width: 1440, height: 900), isBuiltIn: false, isAvailable: true),
            .init(id: 3, frame: CGRect(x: -1920, y: -800, width: 1920, height: 1080), isBuiltIn: false, isAvailable: true),
            .init(id: 4, frame: CGRect(x: 2880, y: 0, width: 1440, height: 900), isBuiltIn: false, isAvailable: false),
        ]
    }
}
