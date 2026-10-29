import Testing
@testable import DisplayDDC

struct VolumeKeyEventTests {
    /// `data1` = key code << 16 | key state << 8 | repeat flag (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    private func data1(key: Int, state: Int, isRepeat: Bool = false) -> Int {
        key << 16 | state << 8 | (isRepeat ? 1 : 0)
    }

    @Test(arguments: [(0, VolumeKeyEvent.Key.volumeUp), (1, .volumeDown), (7, .mute)])
    func decodesVolumeKeys(code: Int, key: VolumeKeyEvent.Key) {
        let event = VolumeKeyEvent(subtype: 8, data1: data1(key: code, state: 0x0A))
        #expect(event == VolumeKeyEvent(key: key, isKeyDown: true, isRepeat: false))
    }

    @Test func decodesKeyUpAndRepeat() {
        #expect(VolumeKeyEvent(subtype: 8, data1: data1(key: 0, state: 0x0B))?.isKeyDown == false)
        #expect(VolumeKeyEvent(subtype: 8, data1: data1(key: 1, state: 0x0A, isRepeat: true))?.isRepeat == true)
    }

    @Test(arguments: [
        (Int16(8), 16 << 16 | 0x0A << 8),   // play/pause key
        (Int16(8), 2 << 16 | 0x0A << 8),    // brightness up
        (Int16(7), 0 << 16 | 0x0A << 8),    // other system-defined subtype
        (Int16(8), 0 << 16 | 0x05 << 8),    // unknown key state
    ])
    func ignoresOtherSystemDefinedEvents(subtype: Int16, data1: Int) {
        #expect(VolumeKeyEvent(subtype: subtype, data1: data1) == nil)
    }
}

struct DisplayVolumeLevelTests {
    @Test(arguments: [
        (0.0, 6.25), (7.0, 12.5), (6.0, 12.5), (13.0, 18.75), (96.0, 100.0), (100.0, 100.0),
    ])
    func volumeUpMovesToNextSixteenthStep(start: Double, expected: Double) {
        var level = DisplayVolumeLevel(volume: start)
        level.apply(.volumeUp, fine: false)
        #expect(level.volume == expected)
    }

    @Test(arguments: [(7.0, 6.25), (14.0, 12.5), (6.0, 0.0), (0.0, 0.0), (100.0, 93.75)])
    func volumeDownMovesToPreviousSixteenthStep(start: Double, expected: Double) {
        var level = DisplayVolumeLevel(volume: start)
        level.apply(.volumeDown, fine: false)
        #expect(level.volume == expected)
    }

    @Test func fineStepsUseSixtyFourths() {
        var level = DisplayVolumeLevel(volume: 50)
        level.apply(.volumeUp, fine: true)
        #expect(level.volume == 51.5625)
    }

    /// Writes are rounded to whole percent; reading 13 back after writing 12.5 must not stall.
    @Test func repeatedStepsAfterRoundTripKeepMoving() {
        var volume = 0.0
        for _ in 0..<16 {
            var level = DisplayVolumeLevel(volume: volume)
            level.apply(.volumeUp, fine: false)
            volume = level.volume.rounded()
        }
        #expect(volume == 100)
    }

    @Test func muteRemembersAndRestoresVolume() {
        var level = DisplayVolumeLevel(volume: 40)
        level.apply(.mute, fine: false)
        #expect(level.isMuted && level.volumeBeforeMute == 40)
        level.apply(.mute, fine: false)
        #expect(level.volume == 40 && !level.isMuted)
    }

    @Test func unmuteWithoutRememberedVolumeUsesDefault() {
        var level = DisplayVolumeLevel(volume: 0, volumeBeforeMute: 0)
        level.apply(.mute, fine: false)
        #expect(level.volume == 50)
    }
}
