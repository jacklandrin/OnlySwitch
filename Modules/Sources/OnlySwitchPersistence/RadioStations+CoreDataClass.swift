import CoreData
import Foundation

/// Hand-written replacement for Xcode's Core Data `class` code generation,
/// which a Swift package cannot rely on. Mirrors "OnlySwitch 3.xcdatamodel".
@objc(RadioStations)
public final class RadioStations: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<RadioStations> {
        NSFetchRequest<RadioStations>(entityName: "RadioStations")
    }

    @NSManaged public var browserStationID: String?
    @NSManaged public var favicon: String?
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var title: String?
    @NSManaged public var url: String?
}

extension RadioStations: Identifiable {}
