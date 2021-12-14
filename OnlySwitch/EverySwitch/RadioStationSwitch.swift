//
//  RadioStationSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import AppKit
import CoreData

let hasRunRadioKey = "hasRunRadioKey"
let radioStationKey = "radioStationKey"
let defaultRadioStations = [["title":"Country Radio", "url":"https://live.leanstream.co/CKRYFM"],
                            ["title":"Dance UK", "url":"http://uk2.internet-radio.com:8024/stream"],
                            ["title":"Box UK", "url":"http://51.75.170.46:6191/stream"]]
class RadioStationSwitch:SwitchProvider {
    static let shared = RadioStationSwitch()
    var type: SwitchType = .radioStation
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .radioStation)
    var barInfo: SwitchBarInfo = SwitchBarInfo(title: "Radio Player".localized(),
                                               onImage: NSImage(systemSymbolName: "radio"),
                                               offImage: NSImage(systemSymbolName: "radio"))
    private var managedObjectContext:NSManagedObjectContext?
    
    var playerItem:RadioPlayerItem = RadioPlayerItem(isPlaying: false, title: "Country Radio", streamUrl: "http://uk2.internet-radio.com:8024/stream", streamInfo: "", id: UUID())
    
    init() {
        switchBarVM.switchOperator = self
        self.managedObjectContext = PersistenceController.shared.container.viewContext
        
        let currentStationIDStr = UserDefaults.standard.string(forKey: radioStationKey)
        if let currentStationIDStr = currentStationIDStr, let currentStationID = UUID(uuidString: currentStationIDStr) {
            let station = RadioStations.fetchRequest(by: currentStationID).first
            guard let station = station else {return}
            setPlayerItem(station: station)
        } else {
            let station = RadioStations.fetchResult.first
            guard let station = station else {return}
            setPlayerItem(station: station)
        }
    }
    
    func setPlayerItem(station:RadioStations) {
        self.playerItem.isPlaying = false
        self.playerItem.title = station.title!
        self.playerItem.streamUrl = station.url!
        self.playerItem.id = station.id!
        self.playerItem.streamInfo = ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            DispatchQueue.main.async {
                self.playerItem.isPlaying = true
            }
            
            return true
        } else {
            DispatchQueue.main.async {
                self.playerItem.isPlaying = false
                self.playerItem.streamInfo = ""
            }
            
            return true
        }
    }
    
    func currentStatus() -> Bool {
        return playerItem.isPlaying
    }
    
    func currentInfo() -> String {
        return playerItem.title
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    private func firstRadioRun() -> Bool {
//        RadioStations.fetchResult.forEach{ station in
//            managedObjectContext?.delete(station)
//            PersistenceController.shared.saveContext()
//        }
        let hasRun = UserDefaults.standard.bool(forKey: hasRunRadioKey)
        if !hasRun {
            UserDefaults.standard.set(true, forKey: hasRunRadioKey)
            UserDefaults.standard.synchronize()
        }
        return !hasRun
    }
    
    func setDefaultRadioStations() {
        if firstRadioRun() {
            guard let managedObjectContext = managedObjectContext else {
                fatalError("No Managed Object Context Available")
            }
            for radioDic in defaultRadioStations {
                let radio = RadioStations(context:managedObjectContext)
                radio.title = radioDic["title"]!
                radio.url = radioDic["url"]!
                radio.id = UUID()
                radio.timestamp = Date()
            }
            PersistenceController.shared.saveContext()
        }
    }
    
}
