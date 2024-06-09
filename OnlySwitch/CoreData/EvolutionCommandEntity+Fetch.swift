//
//  EvolutionCommandEntity+Fetch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/4.
//

import CoreData
import Foundation

extension EvolutionCommandEntity {

    @MainActor static var defaultFetchRequest: NSFetchRequest<EvolutionCommandEntity> {
        let request:NSFetchRequest<EvolutionCommandEntity> = EvolutionCommandEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EvolutionCommandEntity.timestamp, ascending: false)]
        print("fetched the evolution command")
        return request
    }

    @MainActor static func fetchResult() throws -> [EvolutionCommandEntity] {
        try PersistenceController
            .shared
            .container
            .viewContext
            .fetch(EvolutionCommandEntity.defaultFetchRequest)
    }

    static func fetchRequest(by id: UUID) throws -> EvolutionCommandEntity? {
        let predicate = NSPredicate(
            format: "%K = %@", "id" , "\(id)"
        )

        let request = EvolutionCommandEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EvolutionCommandEntity.timestamp, ascending: true)]
        request.predicate = predicate

        return try PersistenceController
            .shared
            .container
            .viewContext
            .fetch(request)
            .first
    }

    static var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }
}
