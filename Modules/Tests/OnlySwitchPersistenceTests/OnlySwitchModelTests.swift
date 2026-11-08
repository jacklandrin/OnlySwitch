import CoreData
import Testing
@testable import OnlySwitchPersistence

@Suite struct OnlySwitchModelTests {
    @Test func modelLoadsFromModuleBundleWithBothEntities() {
        let names = Set(OnlySwitchModel.shared.entitiesByName.keys)
        #expect(names == ["EvolutionCommandEntity", "RadioStations"])
    }

    @Test func entitiesMapToHandWrittenClasses() {
        let entities = OnlySwitchModel.shared.entitiesByName
        #expect(entities["EvolutionCommandEntity"]?.managedObjectClassName == "EvolutionCommandEntity")
        #expect(entities["RadioStations"]?.managedObjectClassName == "RadioStations")
    }

    @Test func inMemoryStoreRoundTripsEvolutionEntity() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)
        let context = controller.container.viewContext
        let entity = EvolutionCommandEntity(context: context)
        entity.id = UUID()
        try context.save()
        let fetched = try context.fetch(EvolutionCommandEntity.fetchRequest())
        #expect(fetched.count == 1)
    }
}
