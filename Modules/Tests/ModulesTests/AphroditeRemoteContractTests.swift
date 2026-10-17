import Foundation
import Testing
@testable import RemoteCore

struct AphroditeRemoteContractTests {
    @Test func capabilityNegotiationExcludesLegacyPeers() throws {
        let legacy = RemoteProtocolVersion(major: 1, minor: 5)
        let current = RemoteProtocolVersion(major: 1, minor: 6)
        #expect(RemoteProtocolVersion.current == current)
        #expect(legacy.supportsAphroditeRemote == false)
        #expect(current.supportsAphroditeRemote)
        #expect(try #require(current.negotiated(with: legacy)).supportsAphroditeRemote == false)
        #expect(try #require(current.negotiated(with: current)).supportsAphroditeRemote)
    }

    @Test func snapshotMessagesRoundTripIncludingChunkBytes() throws {
        let transferID = UUID()
        let appID = UUID()
        let bytes = Data([0, 1, 127, 128, 255])
        let descriptor = try AphroditeRemoteDocumentDescriptor(
            appID: appID, title: "Counter", updatedAt: Date(timeIntervalSince1970: 100),
            byteCount: bytes.count, chunkCount: 1, sha256: Data(repeating: 1, count: 32)
        )
        let manifest = try AphroditeRemoteLibraryManifest(revision: 9, transferID: transferID, documents: [descriptor])
        let chunk = try AphroditeRemoteDocumentChunk(transferID: transferID, appID: appID, index: 0, data: bytes)
        let messages: [RemoteMessage] = [
            .aphroditeLibraryRequest,
            .aphroditeLibraryManifest(manifest),
            .aphroditeDocumentChunk(chunk),
            .aphroditeTransferComplete(transferID),
        ]
        for message in messages {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
        #expect(chunk.data == bytes)
    }

    @Test func emptyManifestCanRemoveAllPreviouslySharedTools() throws {
        let manifest = try AphroditeRemoteLibraryManifest(revision: 10, transferID: UUID(), documents: [])
        #expect(try JSONDecoder().decode(AphroditeRemoteLibraryManifest.self, from: JSONEncoder().encode(manifest)) == manifest)
    }

    @Test(arguments: [0, 65_537])
    func invalidChunkLengthIsRejected(length: Int) {
        #expect(throws: (any Error).self) {
            try AphroditeRemoteDocumentChunk(transferID: UUID(), appID: UUID(), index: 0, data: Data(repeating: 1, count: length))
        }
    }

    @Test func negativeChunkIndexIsRejected() {
        #expect(throws: (any Error).self) {
            try AphroditeRemoteDocumentChunk(transferID: UUID(), appID: UUID(), index: -1, data: Data([1]))
        }
    }

    @Test func malformedDescriptorAndDuplicateIDsAreRejected() throws {
        let id = UUID()
        #expect(throws: (any Error).self) {
            try AphroditeRemoteDocumentDescriptor(appID: id, title: "Tool", updatedAt: .distantPast, byteCount: 1, chunkCount: 1, sha256: Data())
        }
        #expect(throws: (any Error).self) {
            try AphroditeRemoteDocumentDescriptor(appID: id, title: "Tool", updatedAt: .distantPast, byteCount: 65_537, chunkCount: 1, sha256: Data(repeating: 1, count: 32))
        }
        let descriptor = try AphroditeRemoteDocumentDescriptor(appID: id, title: "Tool", updatedAt: .distantPast, byteCount: 1, chunkCount: 1, sha256: Data(repeating: 1, count: 32))
        #expect(throws: (any Error).self) {
            try AphroditeRemoteLibraryManifest(revision: 1, transferID: UUID(), documents: [descriptor, descriptor])
        }
    }

    @Test func malformedChunkCannotBypassValidationThroughDecoding() {
        let json = Data(#"{"transferID":"\#(UUID())","appID":"\#(UUID())","index":-1,"data":"AQ=="}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AphroditeRemoteDocumentChunk.self, from: json) }
    }
    @Test func personalToolRejectsInvalidHTMLAndSVG() {
        #expect(throws: (any Error).self) {
            try AphroditePersonalTool(id: UUID(), title: "Tool", html: "<button>Fragment</button>", updatedAt: .distantPast)
        }
        #expect(throws: (any Error).self) {
            try AphroditePersonalTool(id: UUID(), title: "Tool", html: "<html><body>Tool</body></html>", iconSVG: "<svg><script>alert(1)</script></svg>", updatedAt: .distantPast)
        }
    }

    @Test func cachedSnapshotRejectsDuplicateToolIDs() throws {
        let tool = try AphroditePersonalTool(id: UUID(), title: "Tool", html: "<html><body>Tool</body></html>", updatedAt: .distantPast)
        #expect(throws: (any Error).self) {
            try AphroditeRemoteLibrarySnapshot(revision: 1, apps: [tool, tool]).validated()
        }
    }

}
