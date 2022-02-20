//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

let orderWeightKey = "orderWeightKey"
class SwitchVM: ObservableObject, CurrentScreen {

    @Published var switchList = [SwitchBarVM]()
    @Published var shortcutsList = [ShortcutsBarVM]()
    
    @Published var maxHeight:CGFloat = 0
    
    @Published var allItemList = Array<BarProvider>() //items which should be shown
    
    @Published var uncategoryItemList = Array<SwitchBarVM>() //for two columns
    
    @Published var audioItemList = Array<SwitchBarVM>() //for two columns
    
    @Published var cleanupItemList = Array<SwitchBarVM>() //for two columns
    
    @Published var updateID = UUID() //for refresh UI
    
    @Published var sortMode = false
    
    @UserDefaultValue(key: soundWaveEffectDisplayKey, defaultValue: true)
    var soundWaveEffectDisplay:Bool
    
    @UserDefaultValue(key: appearanceColumnCountKey, defaultValue: SwitchListAppearance.single.rawValue)
    var currentAppearance:String
    
    init() {
        refreshMaxHeight()
    }
    
    private func refreshList() {
        self.refreshMaxHeight()
        self.switchList = SwitchManager.shared.barVMList()
        self.shortcutsList = SwitchManager.shared.shortcutsBarVMList()
    }
    
    private func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
    
    func refreshData() {
        self.sortMode = false
        self.refreshList()
        self.refreshSwitchStatus()
        self.allItemList = self.switchList + self.shortcutsList
        //for sorting
        let orderDic = UserDefaults.standard.dictionary(forKey: orderWeightKey) as? [String:Int] ?? [String:Int]()
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
        self.allItemList = self.allItemList.sorted{$0.weight < $1.weight}
        self.uncategoryItemList = self.switchList.filter{ $0.category == .none && !$0.isHidden }
        self.audioItemList = self.switchList.filter{ $0.category == .audio && !$0.isHidden }
        self.cleanupItemList = self.switchList.filter{ $0.category == .cleanup && !$0.isHidden }
        
        updateID = UUID()
        print("refresh")
    }
    
    
    /// calculate list max height
    func refreshMaxHeight() {
        guard let screen = getScreenWithMouse() else {return}
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
        maxHeight = screen.frame.height - menuBarHeight - 20
        print(maxHeight)
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
        UserDefaults.standard.set(orderDic, forKey: orderWeightKey)
        UserDefaults.standard.synchronize()
    }
}
