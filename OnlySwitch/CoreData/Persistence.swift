//
//  Persistence.swift
//  Test
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let loadError: NSError?

    init(
        inMemory: Bool = false,
        storeURL: URL? = nil,
        legacyStoreURL: URL? = nil,
        managedObjectModel: NSManagedObjectModel? = nil
    ) {
        if let managedObjectModel {
            container = NSPersistentContainer(name: "OnlySwitch", managedObjectModel: managedObjectModel)
        } else {
            container = NSPersistentContainer(name: "OnlySwitch")
        }
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
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        // Initialization and migration finish before callers can use viewContext.
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var startupError: NSError?
        container.loadPersistentStores { _, error in
            startupError = error as NSError?
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

    func requireStore() throws {
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

    func saveContext() {
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

    private static func log(_ error: NSError) {
        NSLog("OnlySwitch persistence error: %@, %@", error, error.userInfo)
    }
}
