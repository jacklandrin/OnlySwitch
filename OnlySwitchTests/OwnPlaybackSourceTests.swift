import Testing
@testable import OnlySwitch

@MainActor
struct OwnPlaybackSourceTests {
    @Test func noRowWhileNothingPlays() {
        #expect(SoundMixerVM.ownPlaybackRow(isPlaying: false, volume: 80, previous: nil, icon: nil) == nil)
    }

    @Test func playingRowUsesPlayerVolumeWithoutAudioProcessing() throws {
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 40, previous: nil, icon: nil))
        #expect(row.id == OwnPlaybackSource.rowID)
        #expect(row.name == "OnlySwitch")
        #expect(row.control == .ownPlayer)
        #expect(row.volume == 40)
        #expect(row.isMuted == false)
        #expect(row.volumeBeforeMute == 40)
        #expect(row.pid == nil)
        #expect(row.processObjectIDs.isEmpty)
    }

    @Test func zeroVolumeIsMutedAndKeepsRestoreLevel() throws {
        let previous = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 70, previous: nil, icon: nil))
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 0, previous: previous, icon: nil))
        #expect(row.isMuted)
        #expect(row.volumeBeforeMute == 70)
    }

    @Test func volumeIsClamped() throws {
        let row = try #require(SoundMixerVM.ownPlaybackRow(isPlaying: true, volume: 140, previous: nil, icon: nil))
        #expect(row.volume == 100)
    }
}
