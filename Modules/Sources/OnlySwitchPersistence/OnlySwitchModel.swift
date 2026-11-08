import CoreData

public enum OnlySwitchModel {
    /// The compiled model lives in this module's resource bundle, not the app bundle.
    /// `NSManagedObjectModel` is not `Sendable`, but it is never mutated after
    /// loading, and Core Data treats a model in use by a coordinator as immutable.
    nonisolated(unsafe) public static let shared: NSManagedObjectModel = {
        guard let url = Bundle.module.url(forResource: "OnlySwitch", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("OnlySwitch.momd is missing from the OnlySwitchPersistence bundle")
        }
        return model
    }()
}
