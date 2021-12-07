//
//  BluetoothSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import Foundation

class BluetoothSwitch:SwitchProvider {
    static let shared = BluetoothSwitch()
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
