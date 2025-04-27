//
//  BluetoothSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import AppKit
import Switches

final class BluetoothSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .bluetooth
    let blManager = BluetoothDevicesManager.shared

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func currentStatus() async -> Bool {
        return blManager.centralManager.state == .poweredOn
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    func operateSwitch(isOn: Bool) async throws {
        blManager.setBluetooth(isOn: isOn)
    }
}
