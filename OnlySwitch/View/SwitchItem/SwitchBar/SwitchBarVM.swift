//
//  SwitchBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI
class SwitchBarVM : BarProvider, ObservableObject, SwitchDelegate {
    var barName: String
    {
        switchType.barInfo().title
    }
  
    @Published var weight: Int = 0
    
    var switchType:SwitchType
    {
        return switchOperator.type
    }
    
    var title:String {
        return switchType.barInfo().title
    }
    
    var onImage:NSImage {
        return switchType.barInfo().onImage
    }
    
    var offImage:NSImage {
        return switchType.barInfo().offImage
    }
    
    var controlType:ControlType {
        return switchType.barInfo().controlType
    }
    
    var category:SwitchCategory {
        return switchType.barInfo().category
    }
    
    @Published var isHidden = false
    @Published var isOn:Bool = false
    @Published var processing = false
    @Published var info = ""
    
    @Published var switchOperator:SwitchProvider
    
    init(switchOperator:SwitchProvider) {
        self.switchOperator = switchOperator
        self.switchOperator.delegate = self
    }
    
    func refreshStatus() {
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
        Task {
            let isOn = await switchOperator.currentStatusAsync()
            DispatchQueue.main.async { [self] in
                self.isOn = isOn
            }
        }
    }
    
    func refreshInfo() {
        Task {
            let info = await switchOperator.currentInfoAsync()
            DispatchQueue.main.async { [self] in
                self.info = info
            }
        }
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
                    let _ = switchOperator.currentStatus()
                    info = switchOperator.currentInfo()
                }
            }
        }
    }
    
    func shouldRefreshIfNeed(aSwitch:SwitchProvider) {
        guard self.switchOperator === aSwitch else {return}
        refreshAsync()
    }
}
