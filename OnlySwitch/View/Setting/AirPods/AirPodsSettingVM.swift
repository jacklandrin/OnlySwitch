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
        Preferences.shared.airPodsAddress = item.address
        if let airpodSwitch = SwitchManager.shared.getSwitch(of: .airPods) as? AirPodsSwitch {
            airpodSwitch.currentDevice = item.device
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.airPods)
        }
    }
    
}
