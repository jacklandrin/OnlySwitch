//
//  BluetoothSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import AppKit

class BluetoothSwitch:SwitchProvider {

    var type: SwitchType = .bluetooth
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .bluetooth)
    var barInfo: SwitchBarInfo = SwitchBarInfo(title: "Bluetooth",
                                               onImage: NSImage(named: "bluetooth_on")!,
                                               offImage: NSImage(named: "bluetooth_off")!)
    init() {
        switchBarVM.switchOperator = self
    }
    let blManager = BluetoothDevicesManager.shared
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return blManager.centralManager.state == .poweredOn
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        blManager.setBluetooth(isOn: isOn)
        return true
    }
}
