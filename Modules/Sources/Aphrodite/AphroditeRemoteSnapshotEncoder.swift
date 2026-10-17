import CryptoKit
import Foundation
import RemoteCore

public enum AphroditeRemoteSnapshotEncoder {
    public static func messages(
        library: AphroditeLibrary,
        revision: UInt64,
        transferID: UUID
    ) throws -> [RemoteMessage] {
        let tools = try library.apps.map { app in
            try AphroditePersonalTool(
                id: app.id,
                title: app.title,
                html: app.html,
                iconSVG: app.iconSVG,
                updatedAt: app.updatedAt
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var documents: [(descriptor: AphroditeRemoteDocumentDescriptor, bytes: Data)] = []
        for tool in tools {
            let bytes = try encoder.encode(tool)
            let descriptor = try AphroditeRemoteDocumentDescriptor(
                appID: tool.id,
                title: tool.title,
                updatedAt: tool.updatedAt,
                byteCount: bytes.count,
                chunkCount: (bytes.count + AphroditeRemoteDocumentDescriptor.maximumChunkBytes - 1)
                    / AphroditeRemoteDocumentDescriptor.maximumChunkBytes,
                sha256: Data(SHA256.hash(data: bytes))
            )
            documents.append((descriptor, bytes))
        }

        let manifest = try AphroditeRemoteLibraryManifest(
            revision: revision,
            transferID: transferID,
            documents: documents.map(\.descriptor)
        )
        var messages: [RemoteMessage] = [.aphroditeLibraryManifest(manifest)]
        for document in documents {
            for index in 0..<document.descriptor.chunkCount {
                let lower = index * AphroditeRemoteDocumentDescriptor.maximumChunkBytes
                let upper = min(
                    lower + AphroditeRemoteDocumentDescriptor.maximumChunkBytes,
                    document.bytes.count
                )
                messages.append(
                    .aphroditeDocumentChunk(
                        try .init(
                            transferID: transferID,
                            appID: document.descriptor.appID,
                            index: index,
                            data: Data(document.bytes[lower..<upper])
                        )
                    )
                )
            }
        }
        messages.append(.aphroditeTransferComplete(transferID))
        return messages
    }
}
