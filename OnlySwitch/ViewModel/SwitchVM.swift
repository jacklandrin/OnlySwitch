//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

class SwitchVM : ObservableObject, CurrentScreen {

    @Published var switchList = [SwitchBarVM]()
    @Published var shortcutsList = [ShortcutsBarVM]()
    
    @Published var maxHeight:CGFloat = 0
    
    init() {
        refreshMaxHeight()
    }
    
    func refreshList() {
        self.refreshMaxHeight()
        self.switchList = SwitchManager.shared.barVMList()
        self.shortcutsList = SwitchManager.shared.shortcutsBarVMList()
        
    }
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
    
    func refreshMaxHeight() {
        guard let screen = getScreenWithMouse() else {return}
        let menuBarHeight = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
        maxHeight = screen.frame.height - menuBarHeight - 20
        print(maxHeight)
    }
    
}
