//
//  Persistence.swift
//  Test
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData
import Extensions
import OSLog

public struct PersistenceController: Sendable {
    // Only the app migrates the shared store. The widget extension can launch
    // alongside the app after an update, and two processes migrating the same
    // SQLite file concurrently makes one of them fail.
    public static let shared = PersistenceController(
        migratesStore: Bundle.main.bundleURL.pathExtension != "appex"
    )

    public let container: NSPersistentContainer
    public let loadError: NSError?

    public init(
        inMemory: Bool = false,
        storeURL: URL? = nil,
        legacyStoreURL: URL? = nil,
        managedObjectModel: NSManagedObjectModel? = nil,
        migratesStore: Bool = true,
        migrationRetryDelays: [TimeInterval] = [0.2, 0.5, 1]
    ) {
        container = NSPersistentContainer(
            name: "OnlySwitch",
            managedObjectModel: managedObjectModel ?? OnlySwitchModel.shared
        )
        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        let defaultURL = legacyStoreURL ?? container.persistentStoreDescriptions.first?.url
        let destinationURL: URL?
        let description: NSPersistentStoreDescription
        if inMemory {
            // Previews and tests must never open or migrate the user's disk stores.
            destinationURL = nil
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            let appGroup = "\(Bundle.appIdentifier)OnlySwitch.shared"
            guard let sharedURL = storeURL ?? FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("onlyswitch.sqlite") else {
                container.persistentStoreDescriptions = []
                let error = NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [NSDebugDescriptionErrorKey: "Shared file container could not be created."]
                )
                loadError = error
                Self.log(error)
                return
            }
            guard migratesStore || FileManager.default.fileExists(atPath: sharedURL.path) else {
                // Creating an empty shared store here would make the app skip
                // relocating the legacy store on its next launch.
                container.persistentStoreDescriptions = []
                let error = NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError,
                    userInfo: [NSDebugDescriptionErrorKey: "The app has not created the shared store yet."]
                )
                loadError = error
                Self.log(error)
                return
            }
            destinationURL = sharedURL
            // An existing shared store is authoritative. Never overwrite it with
            // an older legacy store left behind by a previous migration.
            let legacyURL = defaultURL.flatMap { url in
                FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            let sourceURL = FileManager.default.fileExists(atPath: sharedURL.path)
                ? sharedURL : (legacyURL ?? sharedURL)
            description = NSPersistentStoreDescription(url: sourceURL)
        }

        // Optional Evolution metadata is compatible with lightweight migration.
        description.shouldMigrateStoreAutomatically = migratesStore
        description.shouldInferMappingModelAutomatically = migratesStore
        // Initialization and migration finish before callers can use viewContext.
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var startupError: NSError?
        container.loadPersistentStores { _, error in
            startupError = error as NSError?
        }
        // A process still holding the store, such as the widget extension, can
        // make a migration fail transiently. Once it finishes, the store opens.
        var retryDelays = migratesStore ? migrationRetryDelays[...] : []
        while let error = startupError, Self.isTransientMigrationFailure(error),
              let delay = retryDelays.popFirst() {
            Self.log(error)
            Thread.sleep(forTimeInterval: delay)
            startupError = nil
            container.loadPersistentStores { _, error in
                startupError = error as NSError?
            }
        }

        if startupError == nil,
           let destinationURL,
           let sourceURL = description.url,
           sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
           let store = container.persistentStoreCoordinator.persistentStore(for: sourceURL) {
            do {
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try container.persistentStoreCoordinator.migratePersistentStore(
                    store, to: destinationURL, options: nil, withType: NSSQLiteStoreType
                )
            } catch {
                startupError = error as NSError
            }
            // Keep legacy files intact, including SQLite sidecars, on failure.
            // A successful shared store takes precedence on subsequent launches.
        }

        loadError = startupError
        if let startupError {
            // Prevent callers that save viewContext directly from writing to a
            // legacy store after a failed migration. Removing only detaches the
            // store; it never destroys the user's files.
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores {
                do {
                    try coordinator.remove(store)
                } catch {
                    Self.log(error as NSError)
                }
            }
            Self.log(startupError)
        }
    }

    public func requireStore() throws {
        if let loadError {
            throw loadError
        }
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSPersistentStoreOperationError,
                userInfo: [NSDebugDescriptionErrorKey: "No persistent store is loaded."]
            )
        }
    }

    public func saveContext() {
        // Core Data can raise an Objective-C exception when saving without a store.
        do {
            try requireStore()
        } catch {
            Self.log(error as NSError)
            return
        }
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                Self.log(error as NSError)
            }
        }
    }

    public static func isTransientMigrationFailure(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == NSMigrationError {
            return true
        }
        if error.domain == NSSQLiteErrorDomain, error.code == 5 || error.code == 6 {
            // SQLITE_BUSY and SQLITE_LOCKED.
            return true
        }
        if let sqliteCode = error.userInfo[NSSQLiteErrorDomain] as? Int, sqliteCode == 5 || sqliteCode == 6 {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return isTransientMigrationFailure(underlying)
    }

    private static func log(_ error: NSError) {
        Logger.persistence.error("OnlySwitch persistence error: \(error), \(error.userInfo)")
    }
}
