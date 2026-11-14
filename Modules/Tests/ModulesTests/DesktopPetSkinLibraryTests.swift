import DesktopPetSkinKit
import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetSkinLibraryTests {
    private func makeClient() throws -> (client: DesktopPetSkinLibraryClient, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let suite = "DesktopPetSkinLibraryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let file = dir.appending(path: "DesktopPetSkins.json")
        return (.live(fileURL: file, defaults: defaults), file)
    }

    private func skin(_ name: String = "Cat") -> DesktopPetSkin {
        DesktopPetSkin(
            id: UUID(), name: name, summary: "", createdAt: Date(timeIntervalSinceReferenceDate: 0),
            contractVersion: DesktopPetSkinContract.version, markup: DesktopPetSkinFixture.valid
        )
    }

    @Test func loadingAMissingFileReturnsNoSkins() async throws {
        let (client, _) = try makeClient()
        #expect(await client.load().isEmpty)
        #expect(client.selectedID() == nil)
    }

    @Test func savesLoadsAndDeletes() async throws {
        let (client, _) = try makeClient()
        let cat = skin()
        #expect(try await client.save(cat) == [cat])
        #expect(await client.load() == [cat])
        #expect(try await client.delete(cat.id) == [])
    }

    @Test func savingAnExistingSkinReplacesIt() async throws {
        let (client, _) = try makeClient()
        var cat = skin()
        _ = try await client.save(cat)
        cat.name = "Renamed"
        #expect(try await client.save(cat) == [cat])
    }

    @Test func dropsInvalidSkinsOnLoad() async throws {
        let (client, file) = try makeClient()
        var bad = skin("Bad")
        bad.markup = "<script></script>"
        var future = skin("Future")
        future.contractVersion = DesktopPetSkinContract.version + 1
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([bad, future, skin("Good")]).write(to: file)
        #expect(await client.load().map(\.name) == ["Good"])
    }

    @Test func refusesMoreThanMaximum() async throws {
        let (client, _) = try makeClient()
        for index in 0..<DesktopPetSkinLibraryClient.maximumSkins { _ = try await client.save(skin("\(index)")) }
        await #expect(throws: DesktopPetSkinLibraryError.full) { _ = try await client.save(skin("extra")) }
    }

    @Test func deletingSelectedSkinClearsSelection() async throws {
        let (client, _) = try makeClient()
        let cat = skin()
        _ = try await client.save(cat)
        client.select(cat.id)
        #expect(client.selectedID() == cat.id)
        _ = try await client.delete(cat.id)
        #expect(client.selectedID() == nil)
    }

    @Test func deletingAnotherSkinKeepsSelection() async throws {
        let (client, _) = try makeClient()
        let cat = skin("Cat")
        let dog = skin("Dog")
        _ = try await client.save(cat)
        _ = try await client.save(dog)
        client.select(cat.id)
        #expect(try await client.delete(dog.id) == [cat])
        #expect(client.selectedID() == cat.id)
    }
}
