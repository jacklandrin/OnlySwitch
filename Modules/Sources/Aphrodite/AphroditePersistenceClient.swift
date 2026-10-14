import ComposableArchitecture
import Foundation

public extension Notification.Name {
    static let aphroditeLibraryChanged = Notification.Name("AphroditeLibraryChanged")
}

@DependencyClient
public struct AphroditePersistenceClient: Sendable {
    public enum Error: Swift.Error, Equatable { case corruptStore, loadFailed, writeFailed }

    public var load: @Sendable () async throws -> AphroditeLibrary = { AphroditeLibrary() }
    public var replace: @Sendable (AphroditeLibrary) async throws -> AphroditeLibrary
    public var insert: @Sendable (AphroditeApp, AphroditeModelSelection) async throws -> AphroditeLibrary
    public var delete: @Sendable (UUID) async throws -> AphroditeLibrary
    public var updateSelection: @Sendable (AphroditeModelSelection) async throws -> AphroditeLibrary

    public static func fileSystem(directory: URL) -> Self {
        let store = AphroditeFileStore(directory: directory)
        return Self(
            load: { try await store.load() },
            replace: { try await store.replace($0) },
            insert: { try await store.insert($0, selection: $1) },
            delete: { try await store.delete($0) },
            updateSelection: { try await store.updateSelection($0) }
        )
    }
}

private actor AphroditeFileStore {
    private struct Envelope: Codable { var schemaVersion = 1; var library: AphroditeLibrary }
    let directory: URL
    var didFailLoading = false
    var fileURL: URL { directory.appending(path: "apps.json") }

    init(directory: URL) { self.directory = directory }

    func load() throws -> AphroditeLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { didFailLoading = false; return .init() }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.schemaVersion == 1 else { throw AphroditePersistenceClient.Error.corruptStore }
            guard Set(envelope.library.apps.map(\.id)).count == envelope.library.apps.count,
                  envelope.library.apps.allSatisfy({ $0.html.utf8.count <= AphroditeHTMLExtractor.maximumDocumentBytes }) else {
                throw AphroditePersistenceClient.Error.corruptStore
            }
            didFailLoading = false
            return envelope.library
        } catch let error as AphroditePersistenceClient.Error { didFailLoading = true; throw error }
        catch { didFailLoading = true; throw AphroditePersistenceClient.Error.corruptStore }
    }

    func replace(_ library: AphroditeLibrary) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        guard !didFailLoading else { throw AphroditePersistenceClient.Error.loadFailed }
        guard Self.isValid(library) else { throw AphroditePersistenceClient.Error.writeFailed }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Envelope(library: library))
            try Task.checkCancellation()
            let temporary = directory.appending(path: ".apps-\(UUID().uuidString).json")
            try data.write(to: temporary, options: .atomic)
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: fileURL) }
            NotificationCenter.default.post(name: .aphroditeLibraryChanged, object: nil)
            return library
        } catch is CancellationError {
            throw CancellationError()
        } catch { throw AphroditePersistenceClient.Error.writeFailed }
    }

    func insert(_ app: AphroditeApp, selection: AphroditeModelSelection) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load()
        library.apps.append(app)
        if library.selection == nil {
            library.selection = selection
        }
        return try replace(library)
    }
    func delete(_ id: UUID) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load(); library.apps.removeAll { $0.id == id }; return try replace(library)
    }
    func updateSelection(_ selection: AphroditeModelSelection) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load(); library.selection = selection; return try replace(library)
    }

    private static func isValid(_ library: AphroditeLibrary) -> Bool {
        Set(library.apps.map(\.id)).count == library.apps.count
            && library.apps.allSatisfy { $0.html.utf8.count <= AphroditeHTMLExtractor.maximumDocumentBytes }
    }
}

extension AphroditePersistenceClient: DependencyKey {
    public static let liveValue: Self = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return .fileSystem(directory: applicationSupport.appending(path: "Aphrodite", directoryHint: .isDirectory))
    }()
    public static let testValue = Self()
}

extension DependencyValues {
    public var aphroditePersistence: AphroditePersistenceClient {
        get { self[AphroditePersistenceClient.self] }
        set { self[AphroditePersistenceClient.self] = newValue }
    }
}
