import CoreTransferable
import Foundation

public struct AphroditeSharePayload: Transferable, Sendable {
    public let document: AphroditeShareDocument

    public init(app: AphroditeApp) {
        document = AphroditeShareDocument(app: app)
    }

    init(document: AphroditeShareDocument) {
        self.document = document
    }

    public static func importFile(at url: URL) throws -> Self {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= AphroditeShareDocument.maximumEncodedBytes else {
            throw AphroditeShareDocument.ValidationError.documentTooLarge
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return Self(document: try AphroditeShareDocument.decode(data))
    }

    public var filename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = document.title.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let collapsed = String(scalars).split(whereSeparator: { $0 == " " || $0 == "-" })
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let stem = String((collapsed.isEmpty ? "Mini-App" : collapsed).prefix(64))
        return "\(stem).aphrodite"
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .aphroditeMiniApp) { payload in
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: payload.filename)
            try payload.document.encoded().write(to: url, options: [.atomic, .completeFileProtection])
            return SentTransferredFile(url)
        } importing: { received in
            try Self.importFile(at: received.file)
        }
    }
}
