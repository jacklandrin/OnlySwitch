import Aphrodite
import CryptoKit
import Foundation
import RemoteCore
import Testing

struct AphroditeRemoteSnapshotEncoderTests {
    private let appID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let transferID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test(arguments: [LegacySharingKey.absent, .disabled, .enabled])
    private func everySavedToolAppearsInManifestRegardlessOfLegacySharingKey(
        _ sharingKey: LegacySharingKey
    ) throws {
        let library = try legacyLibrary(sharingKey: sharingKey)

        let transfer = try decodeTransfer(
            AphroditeRemoteSnapshotEncoder.messages(
                library: library,
                revision: 42,
                transferID: transferID
            )
        )

        #expect(transfer.manifest.revision == 42)
        #expect(transfer.manifest.transferID == transferID)
        #expect(transfer.manifest.documents.map(\.appID) == [appID])
        #expect(Set(transfer.documents.keys) == [appID])
        #expect(transfer.completionID == transferID)
    }

    @Test func documentContainsOnlyRemoteRuntimeFields() throws {
        let conversationID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        let app = AphroditeApp(
            id: appID,
            title: "Counter",
            html: completeHTML,
            iconSVG: validIconSVG,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: updatedAt,
            conversationID: conversationID,
            conversation: [
                .init(
                    id: conversationID,
                    prompt: "Private authoring prompt",
                    createdAt: updatedAt
                )
            ]
        )
        let library = AphroditeLibrary(
            apps: [app],
            selection: .init(provider: .openai, model: "private-model-selection")
        )

        let transfer = try decodeTransfer(
            AphroditeRemoteSnapshotEncoder.messages(
                library: library,
                revision: 7,
                transferID: transferID
            )
        )
        let bytes = try #require(transfer.documents[appID])
        let tool = try JSONDecoder().decode(AphroditePersonalTool.self, from: bytes)
        let object = try #require(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )

        #expect(tool.id == appID)
        #expect(tool.title == app.title)
        #expect(tool.html == app.html)
        #expect(tool.iconSVG == app.iconSVG)
        #expect(tool.updatedAt == app.updatedAt)
        #expect(Set(object.keys) == ["formatVersion", "html", "iconSVG", "id", "title", "updatedAt"])
        #expect(object["conversation"] == nil)
        #expect(object["conversationID"] == nil)
        #expect(object["createdAt"] == nil)
        #expect(object["selection"] == nil)
        #expect(object["model"] == nil)
        #expect(object["prompt"] == nil)
        #expect(object["isSharedWithRemote"] == nil)
    }

    @Test func emptyLibrarySendsEmptyManifestAndCompletion() throws {
        let messages = try AphroditeRemoteSnapshotEncoder.messages(
            library: .init(),
            revision: 99,
            transferID: transferID
        )

        #expect(messages.count == 2)
        guard case let .aphroditeLibraryManifest(manifest) = messages[0] else {
            Issue.record("The first message must be the manifest")
            return
        }
        guard case let .aphroditeTransferComplete(completionID) = messages[1] else {
            Issue.record("The last message must complete the transfer")
            return
        }
        #expect(manifest.revision == 99)
        #expect(manifest.transferID == transferID)
        #expect(manifest.documents.isEmpty)
        #expect(completionID == transferID)
    }

    @Test func largeDocumentUsesBoundedContiguousChunksWithMatchingDigest() throws {
        let body = String(repeating: "0123456789abcdef", count: 10_000)
        let app = AphroditeApp(
            id: appID,
            title: "Large Tool",
            html: "<!doctype html><html><head><title>Large</title></head><body>\(body)</body></html>",
            createdAt: .distantPast,
            updatedAt: updatedAt
        )

        let messages = try AphroditeRemoteSnapshotEncoder.messages(
            library: .init(apps: [app]),
            revision: 100,
            transferID: transferID
        )
        let transfer = try decodeTransfer(messages)
        let descriptor = try #require(transfer.manifest.documents.first)
        let chunks = messages.compactMap { message -> AphroditeRemoteDocumentChunk? in
            guard case let .aphroditeDocumentChunk(chunk) = message,
                  chunk.appID == appID else { return nil }
            return chunk
        }
        let bytes = try #require(transfer.documents[appID])

        #expect(descriptor.chunkCount > 1)
        #expect(chunks.map(\.index) == Array(0..<descriptor.chunkCount))
        #expect(chunks.allSatisfy { $0.transferID == transferID })
        #expect(
            chunks.allSatisfy {
                $0.data.count <= AphroditeRemoteDocumentDescriptor.maximumChunkBytes
            }
        )
        #expect(bytes.count == descriptor.byteCount)
        #expect(Data(SHA256.hash(data: bytes)) == descriptor.sha256)
    }

    private func legacyLibrary(sharingKey: LegacySharingKey) throws -> AphroditeLibrary {
        let app = AphroditeApp(
            id: appID,
            title: "Counter",
            html: completeHTML,
            createdAt: .distantPast,
            updatedAt: updatedAt
        )
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(AphroditeLibrary(apps: [app]))
            ) as? [String: Any]
        )
        var apps = try #require(object["apps"] as? [[String: Any]])
        switch sharingKey {
        case .absent:
            apps[0].removeValue(forKey: "isSharedWithRemote")
        case .disabled:
            apps[0]["isSharedWithRemote"] = false
        case .enabled:
            apps[0]["isSharedWithRemote"] = true
        }
        object["apps"] = apps
        return try JSONDecoder().decode(
            AphroditeLibrary.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func decodeTransfer(
        _ messages: [RemoteMessage]
    ) throws -> (
        manifest: AphroditeRemoteLibraryManifest,
        documents: [UUID: Data],
        completionID: UUID
    ) {
        var manifest: AphroditeRemoteLibraryManifest?
        var chunks: [UUID: [AphroditeRemoteDocumentChunk]] = [:]
        var completionID: UUID?
        for message in messages {
            switch message {
            case let .aphroditeLibraryManifest(value):
                manifest = value
            case let .aphroditeDocumentChunk(chunk):
                chunks[chunk.appID, default: []].append(chunk)
            case let .aphroditeTransferComplete(value):
                completionID = value
            default:
                Issue.record("Unexpected message in Aphrodite snapshot")
            }
        }
        let requiredManifest = try #require(manifest)
        var documents: [UUID: Data] = [:]
        for descriptor in requiredManifest.documents {
            let ordered = chunks[descriptor.appID, default: []].sorted { $0.index < $1.index }
            documents[descriptor.appID] = ordered.reduce(into: Data()) { $0.append($1.data) }
        }
        return (requiredManifest, documents, try #require(completionID))
    }
}

private enum LegacySharingKey: CaseIterable, CustomTestStringConvertible, Sendable {
    case absent
    case disabled
    case enabled

    var testDescription: String {
        switch self {
        case .absent: "absent"
        case .disabled: "false"
        case .enabled: "true"
        }
    }
}

private let completeHTML = "<!doctype html><html><head><title>Counter</title></head><body><button>0</button></body></html>"
private let validIconSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect x=\"8\" y=\"8\" width=\"48\" height=\"48\" fill=\"#6750A4\"/></svg>"
