import Testing
@testable import DisplayDDC

struct DDCPacketTests {
    @Test func readRequestMatchesTheIOAVServiceFraming() {
        #expect(DDCPacket.readRequest(vcp: 0x62) == [0x82, 0x01, 0x62, 0x6E ^ 0x82 ^ 0x01 ^ 0x62])
    }

    @Test func writeRequestEncodesBigEndianValue() {
        let checksum: UInt8 = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x62 ^ 0x01 ^ 0x2C
        #expect(DDCPacket.writeRequest(vcp: 0x62, value: 300) == [0x84, 0x03, 0x62, 0x01, 0x2C, checksum])
    }

    /// Captured from an LG UltraFine over DisplayPort: the transport reports the reply's
    /// length byte as 0x51, while the checksum is computed over the standard 0x88.
    @Test func parsesCapturedSpeakerVolumeReply() {
        let reply: [UInt8] = [0x6E, 0x51, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x08, 0xBA]
        #expect(DDCPacket.parseReadReply(reply, vcp: 0x62) == DDCReading(current: 8, maximum: 100))
    }

    @Test func parsesReplyWithStandardLengthByte() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        #expect(DDCPacket.parseReadReply(reply, vcp: 0x10) == DDCReading(current: 100, maximum: 100))
    }

    @Test(arguments: [
        // DDC null message: the display did not answer.
        [0x6E, 0x80, 0xBE, 0x00, 0xE6, 0xD2, 0xD0, 0xA4, 0x0A, 0xF9, 0xAB],
        // Reply for another VCP code.
        [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4],
        // Unsupported VCP code result.
        [0x6E, 0x88, 0x02, 0x01, 0x62, 0x00, 0x00, 0x64, 0x00, 0x08, 0xBB],
        // Corrupted checksum.
        [0x6E, 0x51, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x08, 0xBB],
        // Zero maximum.
        [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 0x00, 0x00, 0x00, 0xD6],
        // Truncated.
        [0x6E, 0x88, 0x02, 0x00, 0x62],
    ] as [[UInt8]])
    func rejectsInvalidSpeakerVolumeReplies(reply: [UInt8]) {
        #expect(DDCPacket.parseReadReply(reply, vcp: 0x62) == nil)
    }
}

struct DDCReadingTests {
    @Test(arguments: [
        (DDCReading(current: 8, maximum: 100), 8),
        (DDCReading(current: 32, maximum: 64), 50),
        (DDCReading(current: 1, maximum: 3), 33),
        (DDCReading(current: 120, maximum: 100), 100),
    ])
    func percentIsScaledAndClamped(reading: DDCReading, percent: Int) {
        #expect(reading.percent == percent)
    }

    @Test(arguments: [(50, 100, 50), (50, 64, 32), (100, 64, 64), (-5, 100, 0), (150, 100, 100), (33, 3, 1)])
    func valueForPercentScalesToDisplayRange(percent: Int, maximum: Int, value: UInt16) {
        #expect(DDCReading.value(forPercent: percent, maximum: maximum) == value)
    }
}

struct DDCDisplayMatcherTests {
    @Test func matchesAudioDeviceByProductNameIgnoringCase() {
        #expect(DDCDisplayMatcher.index(forAudioDeviceNamed: "LG ULTRAFINE",
                                        displayNames: ["DELL U2720Q", "lg UltraFine "]) == 1)
    }

    @Test func singleDisplayIsUsedWhenNamesDiffer() {
        #expect(DDCDisplayMatcher.index(forAudioDeviceNamed: "DisplayPort Audio", displayNames: [nil]) == 0)
    }

    @Test(arguments: [
        [String?](),
        ["DELL U2720Q", "BenQ PD2700U"],
        ["LG ULTRAFINE", "LG ULTRAFINE"],
    ])
    func ambiguousOrMissingDisplayIsNotGuessed(displayNames: [String?]) {
        #expect(DDCDisplayMatcher.index(forAudioDeviceNamed: "LG ULTRAFINE", displayNames: displayNames) == nil)
    }
}
