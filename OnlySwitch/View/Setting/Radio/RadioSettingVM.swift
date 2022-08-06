//
//  RadioSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData
import Combine

class RadioSettingVM:ObservableObject {
    
    @Published private var model = RadioSettingModel()
    private var preferencesPublisher = PreferencesPublisher.shared
    @Published private var preferences = PreferencesPublisher.shared.preferences
    private var cancellables = Set<AnyCancellable>()
    
    var radioList:[RadioPlayerItemViewModel] {
        get {
            model.radioList
        }
        set {
            model.radioList = newValue
        }
    }
    
    var selectRow:RadioPlayerItemViewModel.ID? {
        get {
            return model.selectRow
        }
        set {
            model.selectRow = newValue
            print("select row changed:\(String(describing: selectRow))")
            for radio in radioList where radio.id != selectRow {
                radio.isEditing = false
            }

            model.currentTitle = RadioStationSwitch.shared.playerItem.title
        }
    }
    
    var showErrorToast:Bool {
        get {
            model.showErrorToast
        }
        set {
            model.showErrorToast = newValue
        }
    }
    
    var errorInfo:String {
        model.errorInfo
    }
    
    var currentTitle:String {
        model.currentTitle
    }
    
    var sliderVolume: Float = 1.0
        
    var soundWaveEffectDisplay:Bool {
        get {
            preferences.soundWaveEffectDisplay
        }
        set {
            preferences.soundWaveEffectDisplay = newValue
        }
    }
    
    var sliderValue:Float {
        get {
            preferences.volume
        }
        set {
            preferences.volume = newValue
        }
    }
    
    var allowNotificationChangingStation: Bool {
        get {
            preferences.allNotificationChangingStation
        }
        set {
            preferences.allNotificationChangingStation = newValue
        }
    }
    
    var allowNotificationTrack: Bool {
        get {
            preferences.allNotificationTrack
        }
        set {
            preferences.allNotificationTrack = newValue
        }
    }
    
    var switchEnable:Bool {
        get {
            preferences.radioEnable
        }
        
        set {
            preferences.radioEnable = newValue
            if preferences.radioEnable {
                PlayerManager.shared.player.setupRemoteCommandCenter()
            } else {
                RadioStationSwitch.shared.playerItem.isPlaying = false
                PlayerManager.shared.player.clearCommandCenter()
            }
        }
    }
    
    private var managedObjectContext:NSManagedObjectContext?
    
    init() {
        self.managedObjectContext = PersistenceController.shared.container.viewContext
        RadioStations.fetchResult.forEach{ station in
            let radioItem = RadioPlayerItemViewModel(isPlaying: false,
                                            title: station.title!,
                                            streamUrl: station.url!,
                                            streamInfo: "",
                                            id: station.id!)
            self.model.radioList.append(radioItem)
        }
        
        NotificationCenter.default.addObserver(forName: .illegalRadioInfoNotification,
                                               object: nil,
                                               queue: .main,
                                               using:{[self] notify in
            self.model.errorInfo = notify.object as! String
            self.model.showErrorToast = true
        })
        
        self.model.currentTitle = RadioStationSwitch.shared.playerItem.title
        
        if let newValue = UserDefaults.standard.value(forKey: UserDefaults.Key.volume) as? Float
        {
            sliderVolume = newValue
        }
        
        RadioStationSwitch.shared.playerItem.$model.sink { item in
            guard let item = item else {return}
            if self.radioList.filter({ $0.isEditing == true }).count > 0 {
                self.endEditing()
            }
            self.model.currentTitle = item.title
            self.model.selectRow = item.id
        }.store(in: &cancellables)
        
        preferencesPublisher.$preferences.sink{ _ in
            self.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    func endEditing() {
        for radio in radioList {
            radio.isEditing = false
        }
    }
    
    func selectedItem(id:RadioPlayerItemViewModel.ID?) -> RadioPlayerItemViewModel? {
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
            self.model.showErrorToast = true
            self.model.errorInfo = "At least one radio station"
            return
        }
        guard let currentRow = self.model.selectRow else {
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let managedObjectContext = self.managedObjectContext else {
                fatalError("No Managed Object Context Available")
            }
            if RadioStationSwitch.shared.playerItem.id == currentRow {
                RadioStationSwitch.shared.playerItem.nextStation()
            }
            let station = RadioStations.fetchRequest(by: currentRow).first
            guard let station = station else {return}
            managedObjectContext.delete(station)
            PersistenceController.shared.saveContext()
            let itemIndices = self.radioList.indices.filter{ self.radioList[$0].id == currentRow }
            guard itemIndices.count > 0 else {return}
            self.model.radioList.remove(at: itemIndices.first!)
            self.model.selectRow = nil
        }
        
    }
    
    func addStation() {
        for radio in radioList {
            radio.isEditing = false
        }
        let newStationID = UUID()
        let newStation = RadioPlayerItemViewModel(isPlaying: false, title: "", streamUrl: "", streamInfo: "", id: newStationID)
        self.endEditing()
        newStation.isEditing = true
        self.model.radioList.append(newStation)
        self.model.selectRow = newStationID
    }
    
    func selectStation() {
        for radio in radioList {
            radio.isEditing = false
        }
        guard let currentRow = self.model.selectRow else {
            return
        }
        let station = RadioStations.fetchRequest(by: currentRow).first
        guard let station = station else {return}
        
        RadioStationSwitch.shared.playerItem.isPlaying = false
        RadioStationSwitch.shared.playerItem.title = station.title!
        RadioStationSwitch.shared.playerItem.streamUrl = station.url!
        RadioStationSwitch.shared.playerItem.streamInfo = ""
        RadioStationSwitch.shared.playerItem.id = station.id!
        Preferences.shared.radioStationID = currentRow.uuidString
        self.model.currentTitle = RadioStationSwitch.shared.playerItem.title
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
    }
    
    
}
