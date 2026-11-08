import CoreData
import Foundation

/// Hand-written replacement for Xcode's Core Data `class` code generation,
/// which a Swift package cannot rely on. Mirrors "OnlySwitch 3.xcdatamodel".
@objc(EvolutionCommandEntity)
public final class EvolutionCommandEntity: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<EvolutionCommandEntity> {
        NSFetchRequest<EvolutionCommandEntity>(entityName: "EvolutionCommandEntity")
    }

    @NSManaged public var iconName: String?
    @NSManaged public var id: UUID?
    @NSManaged public var itemType: String?
    @NSManaged public var name: String?
    @NSManaged public var privilegedOperationIdentifier: String?
    @NSManaged public var singleCommand: String?
    @NSManaged public var singleCommandType: String?
    @NSManaged public var statusCommand: String?
    @NSManaged public var statusCommandType: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var trueCondition: String?
    @NSManaged public var turnOffCommand: String?
    @NSManaged public var turnOffCommandType: String?
    @NSManaged public var turnOnCommand: String?
    @NSManaged public var turnOnCommandType: String?
}

extension EvolutionCommandEntity: Identifiable {}
