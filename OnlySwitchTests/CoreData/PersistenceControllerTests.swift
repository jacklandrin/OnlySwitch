import CoreData
import Foundation
import Testing
@testable import OnlySwitch

@MainActor
struct PersistenceControllerTests {
    @Test("In-memory persistence never creates a SQLite database")
    func inMemoryStoreDoesNotTouchDisk() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("unused.sqlite")
        let legacy = directory.appendingPathComponent("legacy.sqlite")
        let model = makeModel()
        try seedStore(at: legacy, model: model, value: "legacy")

        let controller = PersistenceController(
            inMemory: true, storeURL: destination, legacyStoreURL: legacy,
            managedObjectModel: model
        )
        try #require(controller.loadError == nil)
        let store = try #require(controller.container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.type == NSInMemoryStoreType)
        try insert("ephemeral", into: controller.container.viewContext)
        #expect(try values(in: controller.container.viewContext) == ["ephemeral"])
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        #expect(try readStore(at: legacy, model: model) == ["legacy"])
        try close(controller)
    }

    @Test("A newly created SQLite store retains saved records after reopening")
    func newStorePersistsRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("shared/onlyswitch.sqlite")
        let model = makeModel()

        let controller = PersistenceController(
            storeURL: destination,
            legacyStoreURL: directory.appendingPathComponent("absent-legacy.sqlite"),
            managedObjectModel: model
        )
        try #require(controller.loadError == nil)
        try controller.requireStore()
        try insert("saved", into: controller.container.viewContext)
        try close(controller)

        #expect(try readStore(at: destination, model: model) == ["saved"])
    }

    @Test("Migrating a legacy SQLite store preserves its saved records")
    func legacyMigrationPreservesRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.sqlite")
        let destination = directory.appendingPathComponent("shared/onlyswitch.sqlite")
        let model = makeModel()
        try seedStore(at: legacy, model: model, value: "migrated")

        let controller = PersistenceController(
            storeURL: destination, legacyStoreURL: legacy, managedObjectModel: model
        )
        try #require(controller.loadError == nil)
        #expect(try values(in: controller.container.viewContext) == ["migrated"])
        try close(controller)
        #expect(try readStore(at: destination, model: model) == ["migrated"])
    }

    @Test("An existing destination takes precedence without overwriting either database")
    func existingDestinationPreservesBothStores() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.sqlite")
        let destination = directory.appendingPathComponent("onlyswitch.sqlite")
        let model = makeModel()
        try seedStore(at: legacy, model: model, value: "legacy")
        try seedStore(at: destination, model: model, value: "destination")

        let controller = PersistenceController(
            storeURL: destination, legacyStoreURL: legacy, managedObjectModel: model
        )
        try #require(controller.loadError == nil)
        #expect(try values(in: controller.container.viewContext) == ["destination"])
        try close(controller)
        #expect(try readStore(at: legacy, model: model) == ["legacy"])
        #expect(try readStore(at: destination, model: model) == ["destination"])
    }

    @Test("An invalid SQLite store reports failure and preserves its original bytes")
    func invalidStoreReportsFailureWithoutReplacement() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("onlyswitch.sqlite")
        let original = Data("This is not a SQLite database.".utf8)
        try original.write(to: destination)

        let controller = PersistenceController(
            storeURL: destination,
            legacyStoreURL: directory.appendingPathComponent("absent-legacy.sqlite"),
            managedObjectModel: makeModel()
        )

        let loadError = try #require(controller.loadError)
        #expect(controller.container.persistentStoreCoordinator.persistentStores.isEmpty)
        #expect(try Data(contentsOf: destination) == original)
        do {
            try controller.requireStore()
            Issue.record("An unavailable store must reject access before context mutation.")
        } catch {
            let error = error as NSError
            #expect(error.domain == loadError.domain)
            #expect(error.code == loadError.code)
        }
        #expect(controller.container.viewContext.hasChanges == false)
    }

    @Test("Migration failure leaves the legacy database readable and exposes the error")
    func migrationFailurePreservesLegacyStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.sqlite")
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        let destination = blockedParent.appendingPathComponent("onlyswitch.sqlite")
        let model = makeModel()
        try seedStore(at: legacy, model: model, value: "recoverable")
        try Data("blocks destination directory".utf8).write(to: blockedParent)

        let controller = PersistenceController(
            storeURL: destination, legacyStoreURL: legacy, managedObjectModel: model
        )

        #expect(controller.loadError != nil)
        #expect(controller.container.persistentStoreCoordinator.persistentStores.isEmpty)
        #expect(try readStore(at: legacy, model: model) == ["recoverable"])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeModel() -> NSManagedObjectModel {
        let value = NSAttributeDescription()
        value.name = "value"
        value.attributeType = .stringAttributeType
        value.isOptional = false
        let record = NSEntityDescription()
        record.name = "PersistenceTestRecord"
        record.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        record.properties = [value]
        let model = NSManagedObjectModel()
        model.entities = [record]
        return model
    }

    private func insert(_ value: String, into context: NSManagedObjectContext) throws {
        let record = NSEntityDescription.insertNewObject(forEntityName: "PersistenceTestRecord", into: context)
        record.setValue(value, forKey: "value")
        try context.save()
    }

    private func values(in context: NSManagedObjectContext) throws -> [String] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersistenceTestRecord")
        return try context.fetch(request).compactMap { $0.value(forKey: "value") as? String }.sorted()
    }

    private func seedStore(at url: URL, model: NSManagedObjectModel, value: String) throws {
        try withStore(at: url, model: model) { context in
            try insert(value, into: context)
        }
    }

    private func readStore(at url: URL, model: NSManagedObjectModel) throws -> [String] {
        try #require(FileManager.default.fileExists(atPath: url.path))
        return try withStore(at: url, model: model) { context in
            try values(in: context)
        }
    }

    private func withStore<Result>(
        at url: URL,
        model: NSManagedObjectModel,
        operation: (NSManagedObjectContext) throws -> Result
    ) throws -> Result {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return try operation(context)
    }

    private func close(_ controller: PersistenceController) throws {
        controller.container.viewContext.reset()
        let coordinator = controller.container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
