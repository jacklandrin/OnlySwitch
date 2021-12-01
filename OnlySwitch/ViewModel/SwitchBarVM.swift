//
//  SwitchBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI
class SwitchBarVM : ObservableObject, Identifiable {
    @Published var switchType:SwitchType
    @Published var isHidden  = false
    @Published var isOn:Bool = false
    @Published var processing = false
    
    init(switchType:SwitchType) {
        self.switchType = switchType
    }
    
    func refreshStatus() {
        isOn = self.switchType.isOnInitailValue()
        isHidden = !self.switchType.isVisible()
    }
    
    func doSwitch(isOn:Bool) {
        processing = true
        Task {
            let success = await switchType.turnSwitch(isOn: isOn)
            DispatchQueue.main.async { [self] in
                if success {
                    self.isOn = isOn
                }
                self.processing = false
            }
        }
    }
}
