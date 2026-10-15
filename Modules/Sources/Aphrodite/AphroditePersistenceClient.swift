import ComposableArchitecture
import Foundation

public extension Notification.Name {
    static let aphroditeLibraryChanged = Notification.Name("AphroditeLibraryChanged")
}

@DependencyClient
public struct AphroditePersistenceClient: Sendable {
    public enum Error: Swift.Error, Equatable { case corruptStore, loadFailed, writeFailed, missingApp, staleRevision }

    public var load: @Sendable () async throws -> AphroditeLibrary = { AphroditeLibrary() }
    public var replace: @Sendable (AphroditeLibrary) async throws -> AphroditeLibrary
    public var insert: @Sendable (AphroditeApp, AphroditeModelSelection) async throws -> AphroditeLibrary
    public var insertImported: @Sendable (AphroditeApp) async throws -> AphroditeLibrary
    public var delete: @Sendable (UUID) async throws -> AphroditeLibrary
    public var update: @Sendable (AphroditeApp, _ expected: AphroditeApp) async throws -> AphroditeLibrary
    public var updateSelection: @Sendable (AphroditeModelSelection) async throws -> AphroditeLibrary

    public static func fileSystem(directory: URL) -> Self {
        fileSystem(directory: directory, seedVersion: 1) {
            try AphroditeBundledSeed.loadApps()
        }
    }

    static func fileSystem(
        directory: URL,
        seedVersion: Int,
        seedApps: @escaping @Sendable () throws -> [AphroditeApp]
    ) -> Self {
        let store = AphroditeFileStore(
            directory: directory,
            seedVersion: seedVersion,
            seedApps: seedApps
        )
        return Self(
            load: { try await store.load() },
            replace: { try await store.replace($0) },
            insert: { try await store.insert($0, selection: $1) },
            insertImported: { try await store.insertImported($0) },
            delete: { try await store.delete($0) },
            update: { try await store.update($0, expected: $1) },
            updateSelection: { try await store.updateSelection($0) }
        )
    }
}

private actor AphroditeFileStore {
    private struct Envelope: Codable {
        var schemaVersion = 1
        var seedVersion = 0
        var library: AphroditeLibrary

        private enum CodingKeys: String, CodingKey { case schemaVersion, seedVersion, library }

        init(schemaVersion: Int = 1, seedVersion: Int = 0, library: AphroditeLibrary) {
            self.schemaVersion = schemaVersion
            self.seedVersion = seedVersion
            self.library = library
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            seedVersion = try values.decodeIfPresent(Int.self, forKey: .seedVersion) ?? 0
            library = try values.decode(AphroditeLibrary.self, forKey: .library)
        }
    }

    let directory: URL
    let seedVersion: Int
    let seedApps: @Sendable () throws -> [AphroditeApp]
    var didFailLoading = false
    var fileURL: URL { directory.appending(path: "apps.json") }

    init(
        directory: URL,
        seedVersion: Int,
        seedApps: @escaping @Sendable () throws -> [AphroditeApp]
    ) {
        self.directory = directory
        self.seedVersion = seedVersion
        self.seedApps = seedApps
    }

    func load() throws -> AphroditeLibrary {
        do {
            var envelope: Envelope
            if FileManager.default.fileExists(atPath: fileURL.path) {
                envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
            } else {
                envelope = Envelope(library: .init())
            }
            guard envelope.schemaVersion == 1 else { throw AphroditePersistenceClient.Error.corruptStore }
            guard Self.isValid(envelope.library) else {
                throw AphroditePersistenceClient.Error.corruptStore
            }
            if envelope.seedVersion < seedVersion {
                let seeds = try seedApps()
                guard Self.isValid(.init(apps: seeds)) else {
                    throw AphroditePersistenceClient.Error.corruptStore
                }
                let existingIDs = Set(envelope.library.apps.map(\.id))
                envelope.library.apps.append(contentsOf: seeds.filter { existingIDs.contains($0.id) == false })
                envelope.seedVersion = seedVersion
                do {
                    try write(envelope)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw AphroditePersistenceClient.Error.writeFailed
                }
            }
            didFailLoading = false
            return envelope.library
        } catch is CancellationError { throw CancellationError() }
        catch let error as AphroditePersistenceClient.Error { didFailLoading = true; throw error }
        catch { didFailLoading = true; throw AphroditePersistenceClient.Error.corruptStore }
    }

    func replace(_ library: AphroditeLibrary) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        guard !didFailLoading else { throw AphroditePersistenceClient.Error.loadFailed }
        guard Self.isValid(library) else { throw AphroditePersistenceClient.Error.writeFailed }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let currentSeedVersion = try currentEnvelope()?.seedVersion ?? 0
            try write(Envelope(seedVersion: currentSeedVersion, library: library))
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
    func insertImported(_ app: AphroditeApp) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load()
        library.apps.append(app)
        return try replace(library)
    }
    func delete(_ id: UUID) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load(); library.apps.removeAll { $0.id == id }; return try replace(library)
    }
    func update(_ app: AphroditeApp, expected: AphroditeApp) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load()
        guard let index = library.apps.firstIndex(where: { $0.id == expected.id }) else { throw AphroditePersistenceClient.Error.missingApp }
        guard library.apps[index] == expected, app.id == expected.id, app.createdAt == expected.createdAt else { throw AphroditePersistenceClient.Error.staleRevision }
        library.apps[index] = app
        return try replace(library)
    }
    func updateSelection(_ selection: AphroditeModelSelection) throws -> AphroditeLibrary {
        try Task.checkCancellation()
        var library = try load(); library.selection = selection; return try replace(library)
    }

    private static func isValid(_ library: AphroditeLibrary) -> Bool {
        Set(library.apps.map(\.id)).count == library.apps.count
            && library.apps.allSatisfy { $0.html.utf8.count <= AphroditeHTMLExtractor.maximumDocumentBytes }
    }

    private func currentEnvelope() throws -> Envelope? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
    }

    private func write(_ envelope: Envelope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(envelope)
        try Task.checkCancellation()
        let temporary = directory.appending(path: ".apps-\(UUID().uuidString).json")
        try data.write(to: temporary, options: .atomic)
        do {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

enum AphroditeBundledSeed {
    private struct Document: Decodable {
        let seedVersion: Int
        let apps: [AphroditeApp]
    }

    static func loadApps() throws -> [AphroditeApp] {
        let document = try JSONDecoder().decode(Document.self, from: resourceData())
        guard document.seedVersion == 1 else {
            throw AphroditePersistenceClient.Error.corruptStore
        }
        return document.apps
    }

    static func resourceData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "InitialApps", withExtension: "json") else {
            throw AphroditePersistenceClient.Error.corruptStore
        }
        return try Data(contentsOf: url)
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
