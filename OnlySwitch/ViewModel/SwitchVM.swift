//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

class SwitchVM : ObservableObject {

    @Published var switchList = [SwitchBarVM]()
    
    func refreshList() {
        self.switchList = SwitchManager.shared.barVMList()
    }
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
            
}
