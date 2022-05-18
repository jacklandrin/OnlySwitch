//
//  BluetoothDevicesManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/6.
//

import Foundation
import IOBluetooth
import CoreBluetooth

enum AirPodsBattery:String {
    case left = "BatteryPercentLeft"
    case right = "BatteryPercentRight"
    case `case` = "BatteryPercentCase"
}

class BluetoothDevicesManager:NSObject {
    static let shared = BluetoothDevicesManager()
    private let classOfAirpods:UInt32 = 2360344
    private var disconnectComplete:(_ success:Bool, _ errorInfo:String) -> Void = {_,_ in}
    private var connectComplete:(_ success:Bool, _ errorInfo:String) -> Void = {_,_ in}
    private let concurrentQueue = DispatchQueue(label: "concurrentQueue", attributes: .concurrent)
    var centralManager:CBCentralManager!
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    var allPairedDevices:[IOBluetoothDevice] {
        IOBluetoothDevice.pairedDevices().filter{ $0 is IOBluetoothDevice }.map{ $0 as! IOBluetoothDevice }
    }
    
    var allPairedAirpods:[IOBluetoothDevice] {
        allPairedDevices.filter{ $0.classOfDevice == classOfAirpods }
    }
    
    func setBluetooth(isOn:Bool) {
        IOBluetoothPreferenceSetControllerPowerState(isOn ? 1 : 0)
    }
    
    func getAirPodsBattery(device:IOBluetoothDevice) -> String {
        let command = "sh \(scriptDiskFilePath(scriptName: getAirpodsBatteryShell))"
        do {
            let value = try command.runAppleScript(isShellCMD: true)
            let valueGroupedBySpaces = value.split(separator: "\n")
            guard valueGroupedBySpaces.count > 0 else {
                return ""
            }
            var currentAirPodsBattery = ""
            for item in valueGroupedBySpaces {
                let datas = String(item).components(separatedBy: "@@")
                guard datas.count > 1,
                      let address = datas.first,
                      let batteryInfo = datas.last else {
                          continue
                      }
                if address.trimmingCharacters(in: .whitespaces) == device.addressString.convertMacAdrress() {
                    currentAirPodsBattery = batteryInfo
                    break
                }
            }
            return currentAirPodsBattery
        } catch {
            return ""
        }

    }
    
    
    func connect(addressStr:String) -> (Bool, String) {
        if let device = IOBluetoothDevice(addressString: addressStr) {
            return connect(device: device)
        } else {
            return (false, "wrong address")
        }
    }
    
    func connect(device:IOBluetoothDevice) -> (Bool, String) {
        guard device.isPaired() else {
            return (false, "unpaired device")
        }
        
        guard !device.isConnected() else {
            return (false, "device is connected")
            
        }
        
        let result = device.openConnection(nil, withPageTimeout: 20, authenticationRequired: false)
        if result == kIOReturnSuccess {
            return (true, "")
        } else {
            return (false, "connect failed:\(result)")
        }
    }
    
    func disconnect(addressStr:String) -> (Bool, String){
        if let device = IOBluetoothDevice(addressString: addressStr) {
            return disconnect(device: device)
        } else {
            return (false, "wrong address")
        }
    }
    
    func disconnect(device:IOBluetoothDevice) -> (Bool, String) {
        guard device.isPaired() else {
            return (false, "unpaired device")
        }
        
        guard device.isConnected() else {
            return (false, "device is disconnected")
        }
        
        let result = device.closeConnection()
        if result == kIOReturnSuccess {
            return (true, "")
        } else {
            return (false, "disconnect failed:\(result)")
        }
    }
    
}

extension BluetoothDevicesManager:CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Power on")
        case .poweredOff:
            print("Power off")
        case .unsupported:
            print("Unsupported")
        default:
            break
        }
    }
}
