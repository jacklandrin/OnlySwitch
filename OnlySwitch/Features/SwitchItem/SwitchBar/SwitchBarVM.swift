//
//  SwitchBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI
import Switches
import Sharing

class SwitchBarVM : BarProvider, ObservableObject, @MainActor SwitchDelegate {
    @Shared(.appStorage(UserDefaults.Key.hideMenuAfterRunning)) var hideMenuAfterRunningShared: Bool = false
    let refreshSwitchQueue = DispatchQueue(label: "jacklandrin.onlyswitch.refreshswitch",attributes: .concurrent)
    
    var barName: String {
        switchType.barInfo().title
    }
    
    var switchType: SwitchType {
        return switchOperator.type
    }
    
    var title: String {
        return switchType.barInfo().title
    }
    
    var onImage: NSImage? {
        return switchType.barInfo().onImage
    }
    
    var offImage: NSImage? {
        return switchType.barInfo().offImage
    }
    
    var controlType: ControlType {
        return switchType.barInfo().controlType
    }
    
    var category: SwitchCategory {
        return switchType.barInfo().category
    }
    
    var isHidden: Bool {
        return model.isHidden
    }
    
    var isOn: Bool {
        get {
            return model.isOn
        }
        set {
            model.isOn = newValue
        }
    }
    
    var processing: Bool {
        return model.processing
    }
    
    var info: String {
        return model.info
    }

    var weight: Int {
        get {
            return model.weight
        }
        set {
            model.weight = newValue
        }
    }

    var id: String {
        String(switchType.rawValue)
    }

    @Published private var model = SwitchBarModel()
    @Published private(set) var switchOperator:SwitchProvider
    
    @MainActor
    init(switchOperator: SwitchProvider) {
        self.switchOperator = switchOperator
        self.switchOperator.delegate = self
    }
    
    @MainActor
    func refreshStatus() {
        model.isHidden = !switchOperator.isVisible()
        if switchType == .xcodeCache {
            if info == "" || info != "Calculating..." {
                model.info = "Calculating..."
                refreshAsync()
            }
        } else {
            refreshAsync()
        }
    }
    
    @MainActor
    func refreshAsync() {
        self.model.processing = true
        Task {
            let _isOn = await self.switchOperator.currentStatus()
            var _info = ""
            if self.switchType != .airPods {
                _info = await self.switchOperator.currentInfo()
            }
            Task { @MainActor in
                if self.switchType == .airPods {
                    _info = await self.switchOperator.currentInfo()
                }
                self.model.processing = false
                self.model.isOn = _isOn
                self.model.info = _info
            }
        }
    }
    
    @MainActor
    func doSwitch(isOn: Bool) async {
        model.processing = true
        do {
            _ = try await switchOperator.operateSwitch(isOn: isOn)
            self.model.isOn = isOn
            self.model.processing = false
            if info != "" {
                _ = await switchOperator.currentStatus()
                model.info = await switchOperator.currentInfo()
            }
            if hideMenuAfterRunningShared
                && switchType.barInfo().controlType == .Button
                && switchType.barInfo().category == .none {
                NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
            }
        } catch {
            model.processing = false
        }
    }
    
    @MainActor
    func shouldRefreshIfNeed(aSwitch:SwitchProvider) {
        guard switchOperator === aSwitch else {return}
        refreshAsync()
    }
}
