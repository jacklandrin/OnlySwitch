//
//  RadioSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData

let volumeKey = "volumeKey"
let volumeChangeNotification = NSNotification.Name("volumeChange")
let soundWaveEffectDisplayKey = "soundWaveEffectDisplayKey"
let soundWaveToggleNotification = NSNotification.Name("soundWaveToggleNotification")
class RadioSettingVM:ObservableObject {
    @Published var radioList:[RadioPlayerItem] = [RadioPlayerItem]()
    @Published var selectRow:RadioPlayerItem.ID?
    {
        didSet {
            print("select row changed:\(String(describing: selectRow))")
            for radio in radioList where radio.id != selectRow {
                radio.isEditing = false
            }
            
            currentTitle = RadioStationSwitch.shared.playerItem.title
            
        }
    }
    @Published var showErrorToast = false
    @Published var errorInfo = ""
    @Published var currentTitle = ""
    
    @UserDefaultValue(key: soundWaveEffectDisplayKey, defaultValue: true)
    var soundWaveEffectDisplay:Bool{
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: soundWaveToggleNotification, object: nil)
            NotificationCenter.default.post(name: changeSettingNotification, object: nil)
            
        }
    }
    
    var sliderValue: Float = 0.4 {
        willSet	{
            let userInfo = [ "newValue" : newValue ]
            NotificationCenter.default.post(name: volumeChangeNotification, object: nil, userInfo: userInfo)
        }
    }
    
    private var managedObjectContext:NSManagedObjectContext?
    init() {
        self.managedObjectContext = PersistenceController.shared.container.viewContext
        RadioStations.fetchResult.forEach{ station in
            let radioItem = RadioPlayerItem(isPlaying: false,
                                            title: station.title!,
                                            streamUrl: station.url!,
                                            streamInfo: "",
                                            id: station.id!)
            radioList.append(radioItem)
        }
        
        NotificationCenter.default.addObserver(forName: illegalRadioInfoNotification, object: nil, queue: .main, using:{[self] notify in
            self.errorInfo = notify.object as! String
            self.showErrorToast = true
        })
        currentTitle = RadioStationSwitch.shared.playerItem.title
    }
    
    func endEditing() {
        for radio in radioList {
            radio.isEditing = false
        }
    }
    
    func selectedItem(id:RadioPlayerItem.ID?) -> RadioPlayerItem? {
        guard let id = id else {
            return nil
        }

        let item = radioList.filter{ $0.id == id }
        guard item.count > 0 else {return nil}
        return item.first
    }
    
    func deleteStation() {
        for radio in radioList {
            radio.isEditing = false
        }
        guard radioList.count > 1 else {
            showErrorToast = true
            errorInfo = "At least one radio station"
            return
        }
        guard let currentRow = selectRow else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let managedObjectContext = self.managedObjectContext else {
                fatalError("No Managed Object Context Available")
            }
            let station = RadioStations.fetchRequest(by: currentRow).first
            guard let station = station else {return}
            managedObjectContext.delete(station)
            PersistenceController.shared.saveContext()
            let itemIndices = self.radioList.indices.filter{ self.radioList[$0].id == currentRow }
            guard itemIndices.count > 0 else {return}
            self.radioList.remove(at: itemIndices.first!)
            self.selectRow = nil
        }
    }
    
    func addStation() {
        for radio in radioList {
            radio.isEditing = false
        }
        let newStationID = UUID()
        let newStation = RadioPlayerItem(isPlaying: false, title: "", streamUrl: "", streamInfo: "", id: newStationID)
        self.endEditing()
        newStation.isEditing = true
        self.radioList.append(newStation)
        selectRow = newStationID
    }
    
    func selectStation() {
        for radio in radioList {
            radio.isEditing = false
        }
        guard let currentRow = selectRow else {
            return
        }
        let station = RadioStations.fetchRequest(by: currentRow).first
        guard let station = station else {return}
        
        RadioStationSwitch.shared.playerItem.isPlaying = false
        RadioStationSwitch.shared.playerItem.title = station.title!
        RadioStationSwitch.shared.playerItem.streamUrl = station.url!
        RadioStationSwitch.shared.playerItem.streamInfo = ""
        RadioStationSwitch.shared.playerItem.id = station.id!
        UserDefaults.standard.set(currentRow.uuidString, forKey: radioStationKey)
        UserDefaults.standard.synchronize()
        currentTitle = RadioStationSwitch.shared.playerItem.title
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
        
        
    }
}
