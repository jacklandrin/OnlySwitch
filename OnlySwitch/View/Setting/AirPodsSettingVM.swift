//
//  AirPodsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import IOBluetooth

class AirPodsItem:Identifiable {
    var name:String
    var address:String
    var device:IOBluetoothDevice
    init(name:String,
         address:String,
         device:IOBluetoothDevice) {
        self.name = name
        self.address = address
        self.device = device
    }
}

class AirPodsSettingVM:ObservableObject {
    @Published var airPodsList:[AirPodsItem] = [AirPodsItem]()
    init() {
        BluetoothDevicesManager.shared.allPairedAirpods.forEach{ airPods in
            let airPodsItem = AirPodsItem(name: airPods.name,
                                          address: airPods.addressString,
                                          device: airPods)
            airPodsList.append(airPodsItem)
        }
    }
    
    func select(item:AirPodsItem) {
        UserDefaults.standard.set(item.address, forKey: AirPodsAddressKey)
        UserDefaults.standard.synchronize()
        AirPodsSwitch.shared.currentDevice = item.device
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
    }
    
}
