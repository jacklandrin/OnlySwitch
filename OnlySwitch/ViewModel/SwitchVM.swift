//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

class SwitchVM : ObservableObject {

    @Published var switchList = [SwitchBarVM]()
    @Published var shortcutsList = [ShortcutsBarVM]()
    
    func refreshList() {
        self.switchList = SwitchManager.shared.barVMList()
        self.shortcutsList = SwitchManager.shared.shortcutsBarVMList()
    }
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
            
}
