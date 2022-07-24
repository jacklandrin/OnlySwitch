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
    
    var switchType:SwitchType
    {
        return switchOperator.type
    }
    
    var title:String {
        return switchType.barInfo().title
    }
    
    var onImage:NSImage? {
        return switchType.barInfo().onImage
    }
    
    var offImage:NSImage? {
        return switchType.barInfo().offImage
    }
    
    var controlType:ControlType {
        return switchType.barInfo().controlType
    }
    
    var category:SwitchCategory {
        return switchType.barInfo().category
    }
    
    var isHidden:Bool {
        return model.isHidden
    }
    
    var isOn:Bool {
        get {
            return model.isOn
        }
        set {
            model.isOn = newValue
        }
    }
    
    var processing:Bool {
        return model.processing
    }
    
    var info:String {
        return model.info
    }

    var weight : Int {
        get {
            return model.weight
        }
        set {
            model.weight = newValue
        }
    }
    
    @Published private var model = SwitchBarModel()
    @Published private(set) var switchOperator:SwitchProvider
    
    init(switchOperator:SwitchProvider) {
        self.switchOperator = switchOperator
        self.switchOperator.delegate = self
    }
    
    func refreshStatus() {
        model.isHidden = !switchOperator.isVisable()
        if self.switchType == .xcodeCache {
            if self.info == "" || self.info != "Calculating..." {
                self.model.info = "Calculating..."
                refreshAsync()
            }
        } else {
            refreshAsync()
        }
    }
    
    
    func refreshAsync() {
        self.model.processing = true
        DispatchQueue.global().async {
            let _isOn = self.switchOperator.currentStatus()
            let _info = self.switchOperator.currentInfo()
            DispatchQueue.main.async {
                self.model.processing = false
                self.model.isOn = _isOn
                self.model.info = _info
            }
        }
    }
        
    func doSwitch(isOn:Bool) {
        model.processing = true
        Task {
            do {
                _ = try await switchOperator.operationSwitch(isOn: isOn)
                DispatchQueue.main.async { [self] in
                    self.model.isOn = isOn
                    self.model.processing = false
                    if info != "" {
                        let _ = switchOperator.currentStatus()
                        model.info = switchOperator.currentInfo()
                    }
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    model.processing = false
                }
            }
        }
    }
    
    func shouldRefreshIfNeed(aSwitch:SwitchProvider) {
        guard self.switchOperator === aSwitch else {return}
        refreshAsync()
    }
}
