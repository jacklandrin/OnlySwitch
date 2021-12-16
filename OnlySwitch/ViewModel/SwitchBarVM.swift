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
    
    weak var switchOperator:SwitchProvider?
    
    init(switchType:SwitchType) {
        self.switchType = switchType
    }
    
    func refreshStatus() {
        guard let switchOperator = switchOperator else {
            return
        }

        isHidden = !switchOperator.isVisable()
        if self.switchType == .xcodeCache {
            if self.info == "" || self.info != "Calculating..." {
                self.info = "Calculating..."
                refreshAsync()
            }
        } else {
            isOn = switchOperator.currentStatus()
            info = switchOperator.currentInfo()
        }
    }
    
    func refreshAsync() {
        refreshSwitchStatus()
        refreshInfo()
    }
    
    func refreshSwitchStatus() {
        guard let switchOperator = switchOperator else {
            return
        }

        Task {
            let isOn = await switchOperator.currentStatusAsync()
            DispatchQueue.main.async { [self] in
                self.isOn = isOn
            }
        }
    }
    
    func refreshInfo() {
        guard let switchOperator = switchOperator else {
            return
        }
        Task {
            let info = await switchOperator.currentInfoAsync()
            DispatchQueue.main.async { [self] in
                self.info = info
            }
        }
    }
    
    func doSwitch(isOn:Bool) {
        guard let switchOperator = switchOperator else {
            return
        }
        processing = true
        Task {
            let success = await switchOperator.operationSwitch(isOn: isOn)
            DispatchQueue.main.async { [self] in
                if success {
                    self.isOn = isOn
                }
                self.processing = false
                if info != "" {
                    let _ = switchOperator.currentStatus()
                    info = switchOperator.currentInfo()
                }
            }
        }
    }
}
