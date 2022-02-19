//
//  AirPodsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import AppKit
import IOBluetooth

let AirPodsAddressKey = "AirPodsAddressKey"

class AirPodsSwitch:SwitchProvider {
    var delegate: SwitchDelegate?
    var type: SwitchType = .airPods
    
    init() {
        setCurrentDevice()
    }
    var blManager = BluetoothDevicesManager.shared
    var currentDevice:IOBluetoothDevice?
    
    private func setCurrentDevice() {
        let address = UserDefaults.standard.string(forKey: AirPodsAddressKey)
        guard let address = address else {
            currentDevice = blManager.allPairedAirpods.first
            return
        }
        
        let matchDevices = blManager.allPairedAirpods.filter{ $0.addressString == address }
        guard matchDevices.count > 0, let device = matchDevices.first else {
            currentDevice = blManager.allPairedAirpods.first
            return
        }
        currentDevice = device
    }
    
    func currentStatus() -> Bool {
        guard let currentDevice = currentDevice else {return false}
        return currentDevice.isConnected()
    }
    
    func currentInfo() -> String {
        guard let currentDevice = currentDevice else {return ""}
        return blManager.getAirPodsBattery(device: currentDevice)
    }
    
    func isVisable() -> Bool {
        setCurrentDevice()
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
