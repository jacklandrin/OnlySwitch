//
//  RadioPlayerItem.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import Foundation
import CoreData
import Extensions
import Switches

class RadioPlayerItemViewModel:CommonPlayerItem, ObservableObject, Identifiable  {
    
    @Published var model:RadioPlayerItem!
    var isPlaying:Bool
    {
        get {
            self.model.isPlaying
        }
        
        set {
            self.model.isPlaying = newValue
            if newValue {
                PlayerManager.shared.player.play(stream: self)
            } else {
                if let currentItem = PlayerManager.shared.player.currentPlayerItem as? RadioPlayerItemViewModel,
                currentItem === self {
                    PlayerManager.shared.player.stop()
                }
                self.model.streamInfo = ""
            }
        }
    }
    
    var title:String {
        get {
            model.title
        }
        set {
            model.title = newValue
        }
    }
    
    var streamUrl:String {
        get {
            model.streamUrl
        }
        set {
            model.streamUrl = newValue
        }
    }
    
    var streamInfo:String {
        get {
            model.streamInfo
        }
        set {
            model.streamInfo = newValue
        }
    }
    
    var isEditing:Bool
    {
        get {
            model.isEditing
        }
        set {
            if newValue != isEditing && !newValue {
                storeEditedData()
            }
            model.isEditing = newValue
        }
    }
    
    var id:UUID{
        get {
            model.id
        }
        set {
            model.id = newValue
        }
    }
    
    var trackInfo: String {
        get {
            model.streamInfo
        }
        set {
            model.streamInfo = newValue
        }
    }
    
    var url: URL? {
        get {
            URL(string: self.streamUrl)
        }
        set {
            self.streamUrl = newValue?.absoluteString ?? ""
        }
    }
    
    var type: PlayerType = .Radio
    
    private var managedObjectContext:NSManagedObjectContext?
        
    init(isPlaying: Bool,
         title: String,
         streamUrl: String,
         streamInfo:String,
         id:UUID) {

        self.model = RadioPlayerItem(id: id)
        self.model.isPlaying = isPlaying
        self.model.title = title
        self.model.streamUrl = streamUrl
        self.model.streamInfo = streamInfo
        self.managedObjectContext = PersistenceController.shared.container.viewContext
    }
    
    func storeEditedData() {
        self.isPlaying = false
        let station = RadioStations.fetchRequest(by: id).first
        if let station = station {
            guard self.model.title != "" else {
                self.model.title = station.title!
                NotificationCenter.default.post(name: .illegalRadioInfoNotification, object: "title cannot be null")
                return
            }
            guard streamUrl.isValidURL else {
                self.model.streamUrl = station.url!
                NotificationCenter.default.post(name: .illegalRadioInfoNotification, object: "url is invalied")
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
                    RadioStationSwitch.shared.playerItem.streamUrl = self.model.streamUrl
                    RadioStationSwitch.shared.playerItem.title = self.model.title
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .changeSettings, object: nil)
                }
            }
            
        } else {
            guard title != "" else {
                self.model.title = "new radio station"
                self.model.streamUrl = ""
                NotificationCenter.default.post(name: .illegalRadioInfoNotification, object: "title cannot be null")
                return
            }
            guard streamUrl.isValidURL else {
                self.model.streamUrl = ""
                NotificationCenter.default.post(name: .illegalRadioInfoNotification, object: "url is invalied")
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
    
    func nextTrack() {
        nextStation()
    }
    
    func previousTrack() {
        previousStation()
    }
    
    func nextStation() {
        changeStation(action: .next)
    }
    
    func previousStation() {
        changeStation(action: .previous)
    }
    
    private func changeStation(action:ChangeTrackAction) {
        
        let radios = RadioStations.fetchResult
        let currentIndex = radios.indices.filter{ radios[$0].id! == self.id }.first
        guard let currentIndex = currentIndex else {return}
        PlayerManager.shared.player.stop()
        
        let newIndex:Int!
        switch action {
        case .next:
            newIndex = currentIndex < radios.count - 1 ? currentIndex + 1 : 0
        case .previous:
            newIndex = currentIndex > 0 ? currentIndex - 1 : radios.count - 1
        }
         
        let newRadio = radios[newIndex]
        self.model.updateItem(radio: newRadio)
        Preferences.shared.radioStationID = self.model.id.uuidString
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
        if self.isPlaying {
            PlayerManager.shared.player.play(stream: self)
        }
        
    }
}
