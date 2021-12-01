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
                                                  SwitchBarVM(switchType: .mute)]
    @Published var startatLogin = false
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
            
}
