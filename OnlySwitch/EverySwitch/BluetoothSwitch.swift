//
//  BluetoothSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import AppKit

class BluetoothSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .bluetooth
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
