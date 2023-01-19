//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

class SwitchListVM: ObservableObject, CurrentScreen {
    
    @Published private var model = SwitchListModel()
    
    var switchList:[SwitchBarVM] {
        return model.switchList
    }
    
    var shortcutsList:[ShortcutsBarVM] {
        return model.shortcutsList
    }
    
    var maxHeight:CGFloat {
        return model.maxHeight
    }
    
    var allItemList: [BarProvider] {
        return model.allItemList
    }
    
    var uncategoryItemList: [SwitchBarVM] {
        return model.uncategoryItemList
    }
    
    var audioItemList:[SwitchBarVM] {
        return model.audioItemList
    }
    
    var cleanupItemList:[SwitchBarVM] {
        return model.cleanupItemList
    }
    
    var toolItemList:[SwitchBarVM] {
        return model.toolItemList
    }
    
    var sortMode:Bool {
        return model.sortMode
    }
    
    var soundWaveEffectDisplay:Bool {
        return Preferences.shared.soundWaveEffectDisplay
    }
    
    var currentAppearance:String {
        return Preferences.shared.currentAppearance
    }
    
    var showAds:Bool {
        return Preferences.shared.showAds
    }
    
    
    init() {
        refreshMaxHeight()
        receiveSettingWindowOperation()
    }
    
    deinit{
        print("switch list vm deinit")
    }
    
    private func refreshList() {
        self.refreshMaxHeight()
        self.model.switchList = SwitchManager.shared.barVMList()
        self.model.shortcutsList = SwitchManager.shared.shortcutsBarVMList()
    }
    
    private func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
    
    func toggleSortMode() {
        self.model.sortMode.toggle()
    }
    
    func moveItem(from source: IndexSet, to destination: Int) {
        self.model.allItemList.move(fromOffsets: source, toOffset: destination)
    }
    
    func refreshData() {
        self.model.sortMode = false
        self.refreshList()
        self.refreshSwitchStatus()
        self.model.allItemList = self.switchList.filter{!$0.isHidden} + self.shortcutsList
        //for sorting
        let orderDic = UserDefaults.standard.dictionary(forKey: UserDefaults.Key.orderWeight) as? [String:Int] ?? [String:Int]()
        for item in allItemList {
            let type:String
            if item is SwitchBarVM {
                type = "switch-"
            } else {
                type = "shortcuts-"
            }
            let key = type + item.barName
            let weight = orderDic[key] ?? 10000
            item.weight = weight
        }
        //for two columns
        self.model.allItemList = self.allItemList.sorted{$0.weight < $1.weight}
        self.model.uncategoryItemList = self.switchList.filter{ $0.category == .none && !$0.isHidden }
        self.model.audioItemList = self.switchList.filter{ $0.category == .audio && !$0.isHidden }
        self.model.cleanupItemList = self.switchList.filter{ $0.category == .cleanup && !$0.isHidden }
        self.model.toolItemList = self.switchList.filter{ $0.category == .tool && !$0.isHidden }
        
        print("refresh")
    }
    
    func refreshSingleSwitchStatus(type:SwitchType) {
        if let aSwitch = switchList.filter({$0.switchType == type}).first {
            aSwitch.refreshStatus()
        }
    }
    
    /// calculate list max height
    func refreshMaxHeight() {
        guard let screen = getScreenWithMouse() else {return}
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
        self.model.maxHeight = screen.frame.height - menuBarHeight - 20
        print(self.model.maxHeight)
    }
    
    
    /// save the result of sorting
    func saveOrder() {
        var orderDic = [String:Int]()
        for index in self.allItemList.indices {
            let item = allItemList[index]
            item.weight = index
            let type:String
            if item is SwitchBarVM {
                type = "switch-"
            } else {
                type = "shortcuts-"
            }
            let key = type + item.barName
            orderDic[key] = index
        }
        UserDefaults.standard.set(orderDic, forKey: UserDefaults.Key.orderWeight)
        UserDefaults.standard.synchronize()
    }
    
    
}
