import ComposableArchitecture
import Foundation
import CryptoKit
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAphroditeFeatureTests {
    @Test func cachedToolCanBeLoadedAndOpenedWithoutNetworkAccess() async throws {
        let macID = UUID()
        let tool = try AphroditePersonalTool(id: UUID(), title: "Counter", html: "<html><body>Counter</body></html>", updatedAt: .distantPast)
        let snapshot = AphroditeRemoteLibrarySnapshot(revision: 4, apps: [tool])
        let store = TestStore(initialState: RemoteAphroditeFeature.State(selectedMacID: macID)) { RemoteAphroditeFeature() } withDependencies: {
            $0.remotePersistence.loadAphroditeLibrary = { id in #expect(id == macID); return snapshot }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.libraryLoaded(macID, snapshot)) {
            $0.isLoading = false
            $0.apps = [tool]
            $0.revision = 4
        }
        await store.send(.selectApp(tool.id)) { $0.selectedAppID = tool.id }
        await store.send(.selectApp(nil)) { $0.selectedAppID = nil }
    }

    @Test func noSelectedMacDoesNotReadAnyLibrary() async {
        let store = TestStore(initialState: RemoteAphroditeFeature.State()) { RemoteAphroditeFeature() } withDependencies: {
            $0.remotePersistence.loadAphroditeLibrary = { _ in Issue.record("No Mac selected"); return nil }
        }
        await store.send(.task)
        #expect(store.state.apps.isEmpty)
    }

    @Test func absentCacheFinishesWithAnEmptyLibraryAndUnknownToolCannotOpen() async {
        let macID = UUID()
        let store = TestStore(initialState: RemoteAphroditeFeature.State(selectedMacID: macID)) { RemoteAphroditeFeature() } withDependencies: {
            $0.remotePersistence.loadAphroditeLibrary = { _ in nil }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.libraryLoaded(macID, nil)) { $0.isLoading = false }
        await store.send(.selectApp(UUID()))
        #expect(store.state.apps.isEmpty)
        #expect(store.state.selectedAppID == nil)
    }

    @Test func staleMacLoadCannotReplaceCurrentlySelectedMac() async throws {
        let firstMac = UUID()
        let secondMac = UUID()
        let tool = try AphroditePersonalTool(id: UUID(), title: "Old Mac", html: "<html><body>Old</body></html>", updatedAt: .distantPast)
        let snapshot = AphroditeRemoteLibrarySnapshot(revision: 4, apps: [tool])
        let store = TestStore(initialState: RemoteAphroditeFeature.State(selectedMacID: secondMac)) { RemoteAphroditeFeature() }
        await store.send(.libraryLoaded(firstMac, snapshot))
        #expect(store.state.apps.isEmpty)
    }
}

struct RemoteAphroditeSyncTests {
    @Test func completeTransferReassemblesOutOfOrderChunksWithoutChangingDocument() throws {
        let fixture = try transferFixture(large: true)
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        for chunk in fixture.chunks.reversed() { try receiver.append(chunk) }
        #expect(try receiver.complete() == .init(revision: fixture.manifest.revision, apps: [fixture.tool]))
    }

    @Test func missingChunkCannotProduceSnapshot() throws {
        let fixture = try transferFixture(large: true)
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        try receiver.append(fixture.chunks[0])
        #expect(throws: (any Error).self) { try receiver.complete() }
    }

    @Test func duplicateChunkIsRejectedBeforeItCanConsumeMoreStorage() throws {
        let fixture = try transferFixture()
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        try receiver.append(fixture.chunks[0])
        #expect(throws: (any Error).self) { try receiver.append(fixture.chunks[0]) }
    }

    @Test func outOfRangeIndexIsRejected() throws {
        let fixture = try transferFixture()
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        let chunk = try AphroditeRemoteDocumentChunk(transferID: fixture.manifest.transferID, appID: fixture.tool.id, index: fixture.chunks.count, data: Data([1]))
        #expect(throws: (any Error).self) { try receiver.append(chunk) }
    }

    @Test(arguments: [true, false])
    func chunkFromUnrelatedTransferOrAppIsRejected(wrongTransfer: Bool) throws {
        let fixture = try transferFixture()
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        let chunk = try AphroditeRemoteDocumentChunk(transferID: wrongTransfer ? UUID() : fixture.manifest.transferID, appID: wrongTransfer ? fixture.tool.id : UUID(), index: 0, data: Data([1]))
        #expect(throws: (any Error).self) { try receiver.append(chunk) }
    }

    @Test func digestMismatchCannotProduceSnapshot() throws {
        let fixture = try transferFixture()
        let original = fixture.manifest.documents[0]
        let descriptor = try AphroditeRemoteDocumentDescriptor(appID: original.appID, title: original.title, updatedAt: original.updatedAt, byteCount: original.byteCount, chunkCount: original.chunkCount, sha256: Data(repeating: 0, count: 32))
        let manifest = try AphroditeRemoteLibraryManifest(revision: 2, transferID: fixture.manifest.transferID, documents: [descriptor])
        var receiver = RemoteAphroditeTransferAccumulator(manifest: manifest)
        for chunk in fixture.chunks { try receiver.append(chunk) }
        #expect(throws: (any Error).self) { try receiver.complete() }
    }

    @Test(arguments: ["html", "svg", "version", "id", "title", "date"])
    func correctlyHashedInvalidPayloadIsRejected(reason: String) throws {
        let fixture = try transferFixture()
        let encoded = try JSONEncoder().encode(fixture.tool)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        switch reason {
        case "html": object["html"] = "<button>Not a complete HTML document</button>"
        case "svg": object["iconSVG"] = "<svg><script>alert(1)</script></svg>"
        case "version": object["formatVersion"] = 999
        case "id": object["id"] = UUID().uuidString
        case "title": object["title"] = "Different title"
        default: object["updatedAt"] = 1
        }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let descriptor = try AphroditeRemoteDocumentDescriptor(appID: fixture.tool.id, title: fixture.tool.title, updatedAt: fixture.tool.updatedAt, byteCount: bytes.count, chunkCount: 1, sha256: Data(SHA256.hash(data: bytes)))
        let manifest = try AphroditeRemoteLibraryManifest(revision: 2, transferID: fixture.manifest.transferID, documents: [descriptor])
        var receiver = RemoteAphroditeTransferAccumulator(manifest: manifest)
        try receiver.append(.init(transferID: manifest.transferID, appID: fixture.tool.id, index: 0, data: bytes))
        #expect(throws: (any Error).self) { try receiver.complete() }
    }

    @Test func incompleteTransferKeepsPreviousPersistedSnapshotReadable() async throws {
        let fixture = try transferFixture(large: true)
        let macID = UUID()
        let persistence = RemotePersistenceClient.inMemory()
        let previous = AphroditeRemoteLibrarySnapshot(revision: 1, apps: [fixture.tool])
        try await persistence.replaceAphroditeLibrary(macID, previous)
        var receiver = RemoteAphroditeTransferAccumulator(manifest: fixture.manifest)
        try receiver.append(fixture.chunks[0])
        #expect(throws: (any Error).self) { try receiver.complete() }
        #expect(try await persistence.loadAphroditeLibrary(macID) == previous)
    }

    @Test func invalidReplacementSnapshotCannotErasePreviousLibrary() async throws {
        let fixture = try transferFixture()
        let macID = UUID()
        let persistence = RemotePersistenceClient.inMemory()
        let previous = AphroditeRemoteLibrarySnapshot(revision: 1, apps: [fixture.tool])
        try await persistence.replaceAphroditeLibrary(macID, previous)
        await #expect(throws: (any Error).self) {
            try await persistence.replaceAphroditeLibrary(macID, .init(revision: 2, apps: [fixture.tool, fixture.tool]))
        }
        #expect(try await persistence.loadAphroditeLibrary(macID) == previous)
    }

    private func transferFixture(large: Bool = false) throws -> (tool: AphroditePersonalTool, manifest: AphroditeRemoteLibraryManifest, chunks: [AphroditeRemoteDocumentChunk]) {
        let body = large ? String(repeating: "x", count: 70_000) : "Counter"
        let tool = try AphroditePersonalTool(id: UUID(), title: "Counter", html: "<html><body>\(body)</body></html>", updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let bytes = try JSONEncoder().encode(tool)
        let limit = AphroditeRemoteDocumentDescriptor.maximumChunkBytes
        let count = (bytes.count + limit - 1) / limit
        let descriptor = try AphroditeRemoteDocumentDescriptor(appID: tool.id, title: tool.title, updatedAt: tool.updatedAt, byteCount: bytes.count, chunkCount: count, sha256: Data(SHA256.hash(data: bytes)))
        let manifest = try AphroditeRemoteLibraryManifest(revision: 2, transferID: UUID(), documents: [descriptor])
        let chunks = try (0..<count).map { index in
            try AphroditeRemoteDocumentChunk(transferID: manifest.transferID, appID: tool.id, index: index, data: bytes.subdata(in: (index * limit)..<min(bytes.count, (index + 1) * limit)))
        }
        return (tool, manifest, chunks)
    }
}
