//
//  RadioPlayerItem.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import Foundation
import CoreData

let illegalRadioInfoNotification = NSNotification.Name("illegalRadioInfoNotification")

class RadioPlayerItem:ObservableObject, Identifiable {
    @Published var isPlaying:Bool
    {
        didSet {
            if isPlaying {
                PlayerManager.shared.player.play(stream: self)
            } else {
                PlayerManager.shared.player.stop()
                self.streamInfo = ""
            }
        }
    }
    @Published var title:String
    @Published var streamUrl:String
    @Published var streamInfo:String
    @Published var isEditing:Bool = false
    {
        willSet {
            if isEditing {
                storeEditedData()
            }
        }
    }
    
    var id:UUID
    private var managedObjectContext:NSManagedObjectContext?
        
    init(isPlaying: Bool,
         title: String,
         streamUrl: String,
         streamInfo:String,
         id:UUID) {
        self.isPlaying = isPlaying
        self.title = title
        self.streamUrl = streamUrl
        self.streamInfo = streamInfo
        self.id = id
        self.managedObjectContext = PersistenceController.shared.container.viewContext
    }
    
    func storeEditedData() {
        self.isPlaying = false
        let station = RadioStations.fetchRequest(by: id).first
        if let station = station {
            guard title != "" else {
                title = station.title!
                NotificationCenter.default.post(name: illegalRadioInfoNotification, object: "title cannot be null")
                return
            }
            guard streamUrl.isValidURL else {
                streamUrl = station.url!
                NotificationCenter.default.post(name: illegalRadioInfoNotification, object: "url is invalied")
                return
            }
            var hasChanged = false
            if station.title != title {
                station.title = title
                hasChanged = true
            }
            
            if station.url != streamUrl {
                station.url = streamUrl
                hasChanged = true
            }
            if hasChanged {
                PersistenceController.shared.saveContext()
                if RadioStationSwitch.shared.playerItem.id == id {
                    RadioStationSwitch.shared.playerItem.streamUrl = self.streamUrl
                    RadioStationSwitch.shared.playerItem.title = self.title
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .changeSettings, object: nil)
                }
            }
            
        } else {
            guard title != "" else {
                title = "new radio station"
                streamUrl = ""
                NotificationCenter.default.post(name: illegalRadioInfoNotification, object: "title cannot be null")
                return
            }
            guard streamUrl.isValidURL else {
                streamUrl = ""
                NotificationCenter.default.post(name: illegalRadioInfoNotification, object: "url is invalied")
                return
            }
            guard let managedObjectContext = self.managedObjectContext else {
                fatalError("No Managed Object Context Available")
            }
            let radio = RadioStations(context:managedObjectContext)
            radio.title = title
            radio.url = streamUrl
            radio.id = id
            radio.timestamp = Date()
            PersistenceController.shared.saveContext()
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
        
    }
    
    
}
