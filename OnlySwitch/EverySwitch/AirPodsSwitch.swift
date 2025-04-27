//
//  AirPodsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import AppKit
import IOBluetooth
import Switches
import Defines

final class AirPodsSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .airPods
    
    init() {
        setCurrentDevice()
    }
    var blManager = BluetoothDevicesManager.shared
    var currentDevice:IOBluetoothDevice?
    
    private func setCurrentDevice() {
        let address = Preferences.shared.airPodsAddress
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

    @MainActor
    func currentStatus() async -> Bool {
        guard let currentDevice = currentDevice else {return false}
        return currentDevice.isConnected()
    }

    @MainActor
    func currentInfo() async -> String {
        guard let currentDevice else { return "" }
        return await blManager.getAirPodsBattery(device: currentDevice)
    }
    
    func isVisible() -> Bool {
        setCurrentDevice()
        guard blManager.centralManager.state == .poweredOn else {return false}
        guard let currentDevice = currentDevice, currentDevice.isPaired() else {return false}
        return true
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        guard let currentDevice = currentDevice else {
            throw SwitchError.OperationFailed
        }

        if isOn {
            let result = blManager.connect(device: currentDevice)
            if !result.0 {
                print(result.1)
                throw SwitchError.OperationFailed
            }
        } else {
            let result = blManager.disconnect(device: currentDevice)
            if !result.0 {
                print(result.1)
                throw SwitchError.OperationFailed
            }
        }
    }
}
