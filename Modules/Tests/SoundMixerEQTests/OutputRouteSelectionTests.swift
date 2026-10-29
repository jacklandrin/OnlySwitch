import Foundation
import Testing
@testable import SoundMixerEQ

struct OutputRouteSelectionTests {
    @Test func selectionIsSortedUniqueAndBounded() {
        let value = OutputRouteSelection(deviceUIDs: ["b", "", "a", "b", " \n "])
        #expect(value.deviceUIDs == ["a", "b"])
        let bounded = OutputRouteSelection(deviceUIDs: (0..<20).map { String(format: "device-%02d", $0) })
        #expect(bounded.deviceUIDs.count == 16)
        var full = bounded
        full.toggle("extra")
        #expect(full == bounded)
    }

    @Test func lastRemovalReturnsToFollowingSystem() {
        var selection = OutputRouteSelection(deviceUIDs: ["speaker"])
        selection.toggle("speaker")
        #expect(selection.followsSystem)
        selection.toggle("")
        #expect(selection.followsSystem)
    }

    @Test func decodingNormalizesPersistedSelection() throws {
        let json = Data(#"{"deviceUIDs":["b","a","b",""]}"#.utf8)
        let selection = try JSONDecoder().decode(OutputRouteSelection.self, from: json)
        #expect(selection.deviceUIDs == ["a", "b"])
        #expect(try JSONDecoder().decode(OutputRouteSelection.self, from: JSONEncoder().encode(selection)) == selection)
    }

    @Test func partialResolutionPreservesMissingIntent() {
        let selection = OutputRouteSelection(deviceUIDs: ["a", "b"])
        let resolution = OutputRouteResolution(selection: selection, devices: [device("a", isDefault: true)])
        #expect(resolution.onlineUIDs == ["a"])
        #expect(resolution.missingUIDs == ["b"])
        #expect(resolution.isWaiting == false)
        #expect(resolution.requiresTap)
        #expect(selection.deviceUIDs == ["a", "b"])
    }

    @Test func allMissingWaitsWithoutClaimingEffectiveRouting() {
        let resolution = OutputRouteResolution(selection: .init(deviceUIDs: ["gone"]), devices: [device("other", isDefault: true)])
        #expect(resolution.onlineUIDs.isEmpty)
        #expect(resolution.missingUIDs == ["gone"])
        #expect(resolution.isWaiting)
        #expect(resolution.requiresTap == false)
    }

    @Test func followSystemTracksDefaultWhileExplicitDefaultRemainsExplicit() {
        let first = OutputRouteResolution(selection: .init(), devices: [device("a", isDefault: true), device("b")])
        let changed = OutputRouteResolution(selection: .init(), devices: [device("a"), device("b", isDefault: true)])
        #expect(first.onlineUIDs == ["a"])
        #expect(changed.onlineUIDs == ["b"])
        #expect(first.requiresTap == false)
        #expect(changed.requiresTap == false)
        let explicit = OutputRouteResolution(selection: .init(deviceUIDs: ["a"]), devices: [device("a", isDefault: true)])
        #expect(explicit.requiresTap)
    }

    private func device(_ id: String, isDefault: Bool = false) -> OutputRouteDevice {
        .init(id: id, name: id, isDefault: isDefault, channelCount: 2)
    }
}
