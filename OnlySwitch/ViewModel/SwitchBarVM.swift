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
    @Published var info = ""
    
    private let switchOperator:SwitchProvider
    
    init(switchType:SwitchType) {
        self.switchType = switchType
        self.switchOperator = switchType.switchOperator()
    }
    
    func refreshStatus() {
        isHidden = !self.switchOperator.isVisable()
        isOn = self.switchOperator.currentStatus()
        info = self.switchOperator.currentInfo()
    }
    
    func doSwitch(isOn:Bool) {
        processing = true
        Task {
            let success = await switchOperator.operationSwitch(isOn: isOn)
            DispatchQueue.main.async { [self] in
                if success {
                    self.isOn = isOn
                }
                self.processing = false
                if info != "" {
                    let _ = self.switchOperator.currentStatus()
                    info = self.switchOperator.currentInfo()
                }
            }
        }
    }
}
