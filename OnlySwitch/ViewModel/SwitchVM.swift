//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

class SwitchVM : ObservableObject {
    @Published var switchList:[SwitchBarVM] = [SwitchBarVM(switchType: .hiddeDesktop),
                                               SwitchBarVM(switchType: .darkMode),
                                               SwitchBarVM(switchType: .topNotch),
                                               SwitchBarVM(switchType: .mute),
                                               SwitchBarVM(switchType: .screenSaver),
                                               SwitchBarVM(switchType: .nightShift),
                                               SwitchBarVM(switchType: .autohideDock)]

    
    @Published var showSettingMenu = false
    {
        didSet {
            OtherPopover.hasShown(showSettingMenu)
        }
    }
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
            
}
