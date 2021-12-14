//
//  SwitchManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Foundation
import AppKit


class SwitchManager {
    static let shared = SwitchManager()
    
    private var switchMap = [SwitchType: SwitchProvider?]()
    
    func register(aswitch:SwitchProvider) {
        switchMap[aswitch.type] = aswitch
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
    }
    
    func unregister(for type:SwitchType) {
        switchMap.removeValue(forKey: type)
        switchMap[type]? = nil
        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
    }
    
    func getSwitch(of type:SwitchType) -> SwitchProvider? {
        return switchMap[type] ?? nil
    }
    
    func barVMList() -> [SwitchBarVM] {
        let sortedSwitchMap = switchMap.sorted() {$0.key.rawValue < $1.key.rawValue}
        var switchBarVMs = [SwitchBarVM]()
        for (_, value) in sortedSwitchMap {
            if let aswitch = value {
                switchBarVMs.append(aswitch.switchBarVM)
            }
        }
        return switchBarVMs
    }
    
    func registerAllSwitches() {
        self.register(aswitch: HiddenDesktopSwitch())
        self.register(aswitch: DarkModeSwitch())
        self.register(aswitch: TopNotchSwitch())
        self.register(aswitch: MuteSwitch())
        self.register(aswitch: ScreenSaverSwitch())
        self.register(aswitch: NightShiftSwitch())
        self.register(aswitch: AutohideDockSwitch())
        self.register(aswitch: AirPodsSwitch())
        self.register(aswitch: BluetoothSwitch())
        self.register(aswitch: XcodeCacheSwitch())
        self.register(aswitch: AutohideMenuBarSwitch())
        self.register(aswitch: HiddenFilesSwitch())
        self.register(aswitch: RadioStationSwitch.shared)
        self.register(aswitch: KeepAwakeSwitch())
    }
}
