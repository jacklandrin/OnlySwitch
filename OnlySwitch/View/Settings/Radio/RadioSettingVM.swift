//
//  RadioSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import CoreData
import Combine
import AppKit
import Extensions
import Switches

@MainActor
class RadioSettingVM: ObservableObject {

    @Published fileprivate var model = RadioSettingModel()
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    private var cancellables = Set<AnyCancellable>()

    var radioList: [RadioPlayerItemViewModel] {
        get {
            model.radioList
        }
        set {
            model.radioList = newValue
        }
    }

    var selectRow: RadioPlayerItemViewModel.ID? {
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

    var showErrorToast: Bool {
        get {
            model.showErrorToast
        }
        set {
            model.showErrorToast = newValue
        }
    }

    var showSuccessToast: Bool {
        get {
            model.showSuccessToast
        }
        set {
            model.showSuccessToast = newValue
        }
    }

    var successInfo: String {
        model.successInfo
    }

    var errorInfo: String {
        model.errorInfo
    }

    var currentTitle: String {
        model.currentTitle
    }

    var sliderVolume: Float = 1.0

    var soundWaveEffectDisplay: Bool {
        get {
            preferences.soundWaveEffectDisplay
        }
        set {
            preferences.soundWaveEffectDisplay = newValue
        }
    }

    var sliderValue: Float {
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

    var switchEnable: Bool {
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

    var isTipPopover:Bool {
        get {
            model.isTipPopover
        }
        set {
            model.isTipPopover = newValue
        }
    }

    private var managedObjectContext: NSManagedObjectContext?

    init() {
        self.managedObjectContext = PersistenceController.shared.container.viewContext
        let stations = RadioStations.fetchResult

        let uniqueStations = stations.unique { $0.id }
        let unneededStations = stations.filter { station in
            !uniqueStations.contains { $0.objectID == station.objectID }
        }

        unneededStations.forEach { station in
            managedObjectContext?.delete(station)
        }

        for station in stations {
            let radio = RadioPlayerItemViewModel(
                isPlaying: false,
                title: station.title!,
                streamUrl: station.url!,
                streamInfo: "",
                id: station.id!
            )
            radioList.append(radio)
        }

        NotificationCenter.default.addObserver(forName: .illegalRadioInfoNotification,
                                               object: nil,
                                               queue: .main) { @Sendable [self] notify in
            Task { @MainActor in
                self.model.errorInfo = notify.object as! String
                self.model.showErrorToast = true
            }
        }

        self.model.currentTitle = RadioStationSwitch.shared.playerItem.title

        if let newValue = UserDefaults.standard.value(forKey: UserDefaults.Key.volume) as? Float {
            sliderVolume = newValue
        }

        RadioStationSwitch.shared.playerItem.$model.sink { [weak self] item in
            guard let item, let self else { return }
            if self.radioList.filter({ $0.isEditing == true }).count > 0 {
                self.endEditing()
            }
            self.model.currentTitle = item.title
            self.model.selectRow = item.id
        }
        .store(in: &cancellables)

        preferencesPublisher.$preferences.sink{ _ in
            self.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
    }

    func endEditing() {
        for radio in radioList {
            radio.isEditing = false
        }
    }

    private func startEditing() {
        for radio in radioList {
            radio.isEditing = false
        }
    }

    func deleteStation() {
        self.endEditing()
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

    func addStation(title: String = "", streamUrl: String = "") {
        startEditing()
        let newStationID = UUID()
        let newStation = RadioPlayerItemViewModel(isPlaying: false, title: title, streamUrl: streamUrl, streamInfo: "", id: newStationID)
        endEditing()
        newStation.isEditing = true
        newStation.isEditing = title == ""
        model.radioList.append(newStation)
        model.selectRow = newStationID
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
        let isPlaying = RadioStationSwitch.shared.playerItem.isPlaying
        RadioStationSwitch.shared.playerItem.title = station.title!
        RadioStationSwitch.shared.playerItem.streamUrl = station.url!
        RadioStationSwitch.shared.playerItem.streamInfo = ""
        RadioStationSwitch.shared.playerItem.id = station.id!
        Preferences.shared.radioStationID = currentRow.uuidString
        model.currentTitle = RadioStationSwitch.shared.playerItem.title
        RadioStationSwitch.shared.playerItem.isPlaying = isPlaying
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
    }
}

extension RadioSettingVM {
    func exportList() {
        let list = self.model.radioList.map{RadioItem(name: $0.title, url: $0.url?.absoluteString ?? "")}
        guard !list.isEmpty else {return}
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let listJsonStr = try String(data: encoder.encode(list), encoding: .utf8) {
                let newListJsonStr = listJsonStr.replacingOccurrences(of: "\\", with: "")
                let savePanel = buildSavePanel()
                savePanel.begin { (result: NSApplication.ModalResponse) -> Void in
                    if result == NSApplication.ModalResponse.OK {
                        if let panelURL = savePanel.url {
                            try? newListJsonStr.write(to: panelURL, atomically: true, encoding: .utf8)
                            self.model.successInfo = "Success"
                            self.model.showSuccessToast = true
                        }
                    }
                }
            }
        } catch {
            self.model.errorInfo = error.localizedDescription
            self.model.showErrorToast = true
        }

    }

    func importList() {
        let openPanel = buildOpenPanel()
        openPanel.begin{ (result: NSApplication.ModalResponse) -> Void in
            if result == NSApplication.ModalResponse.OK {
                if let openURL = openPanel.url {
                    do {
                        let jsonData = try Data(contentsOf: openURL)
                        let importRadioList = try JSONDecoder().decode([RadioItem].self, from: jsonData)
                        print("name: \(String(describing: importRadioList.first?.name))  url: \(String(describing: importRadioList.first?.url))")
                        for item in importRadioList {
                            if item.url.isValidURL && !RadioStations.existence(url: item.url) {
                                self.addStation(title: item.name, streamUrl: item.url)

                            }
                        }
                        self.model.successInfo = "Success"
                        self.model.showSuccessToast = true
                    } catch {
                        self.model.errorInfo = error.localizedDescription
                        self.model.showErrorToast = true
                    }
                }
            }
        }
    }

    private func buildOpenPanel() -> NSOpenPanel {
        let openPanel = NSOpenPanel()
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.json]
        return openPanel
    }

    private func buildSavePanel() -> NSSavePanel {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Radio List"
        savePanel.nameFieldStringValue = "radio_list"
        savePanel.allowedContentTypes = [.json]
        return savePanel
    }
}
