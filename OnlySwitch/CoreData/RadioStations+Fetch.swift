//
//  RadioStations+Fetch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/4.
//

import CoreData
import Extensions
import Foundation

extension RadioStations {
    static func backupEntries() -> [RadioStationBackup] {
        fetchResult.compactMap { station in
            guard let title = station.title, let url = station.url else { return nil }
            return RadioStationBackup(title: title, url: url)
        }
    }

    /// Adds stations whose URL isn't stored yet, so re-importing a backup never duplicates.
    static func restore(_ stations: [RadioStationBackup]) throws {
        let context = PersistenceController.shared.container.viewContext
        for station in stations where station.url.isValidURL && !existence(url: station.url) {
            let radio = RadioStations(context: context)
            radio.title = station.title
            radio.url = station.url
            radio.id = UUID()
            radio.timestamp = Date()
        }
        if context.hasChanges {
            try context.save()
        }
    }

    static var defaultFetchRequest: NSFetchRequest<RadioStations> {
        let request: NSFetchRequest<RadioStations> = RadioStations.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RadioStations.timestamp, ascending: true)]
        print("fetched the radio stations")
        return request
    }

    static var fetchResult: [RadioStations] {
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

