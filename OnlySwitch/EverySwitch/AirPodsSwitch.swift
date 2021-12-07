//
//  AirPodsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import Foundation
import IOBluetooth

class AirPodsSwitch:SwitchProvider {
    static let shared = AirPodsSwitch()
    var blManager = BluetoothDevicesManager.shared
    var currentDevice:IOBluetoothDevice?
    
    func currentStatus() -> Bool {
        guard let currentDevice = currentDevice else {return false}
        return currentDevice.isConnected()
    }
    
    func currentInfo() -> String {
        guard let currentDevice = currentDevice else {return ""}
        return blManager.getAirPodsBattery(device: currentDevice)
    }
    
    func isVisable() -> Bool {
        currentDevice = blManager.allPairedAirpods.first
        guard blManager.centralManager.state == .poweredOn else {return false}
        guard let currentDevice = currentDevice, currentDevice.isPaired() else {return false}
        return true
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        guard let currentDevice = currentDevice else {return false}
        if isOn {
            let result = blManager.connect(device: currentDevice)
            if !result.0 {
                print(result.1)
            }
            return result.0
        } else {
            let result = blManager.disconnect(device: currentDevice)
            if !result.0 {
                print(result.1)
            }
            return result.0
        }
    }
}
