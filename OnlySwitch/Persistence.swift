//
//  Persistence.swift
//  Test
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "OnlySwitch")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
    
    func saveContext() {
        let context = self.container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

extension RadioStations {
    static var defaultFetchRequest:NSFetchRequest<RadioStations> {
        let request:NSFetchRequest<RadioStations> = RadioStations.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RadioStations.timestamp, ascending: true)]
        print("fetched the radio stations")
        return request
    }
    
    static var fetchResult:[RadioStations] {
        do {
            let fetchResults = try PersistenceController
                .shared
                .container
                .viewContext
                .fetch(RadioStations.defaultFetchRequest)
            if fetchResults.count > 0 {
                return fetchResults
            }
        } catch {
            
        }
        return [RadioStations]()
    }
    
    static func fetchRequest(by ID:UUID) -> [RadioStations] {
        let predicate = NSPredicate(
            format: "%K = %@", "id" , "\(ID)"
        )
        
        let request:NSFetchRequest<RadioStations> = RadioStations.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RadioStations.timestamp, ascending: true)]
        request.predicate = predicate
        
        do{
            let fetchResults = try PersistenceController
                .shared
                .container
                .viewContext
                .fetch(request)
            if fetchResults.count > 0 {
                return fetchResults
            }
        } catch {
            
        }
        return [RadioStations]()
    }
    
    static func existence(url:String) -> Bool {
        let predicate = NSPredicate(
            format: "%K = %@", "url" , "\(url)"
        )
        
        let request:NSFetchRequest<RadioStations> = RadioStations.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RadioStations.timestamp, ascending: true)]
        request.predicate = predicate
        
        do{
            let fetchResults = try PersistenceController
                .shared
                .container
                .viewContext
                .fetch(request)
            if fetchResults.count > 0 {
                return true
            }
        } catch {
            
        }
        return false
    }
}

