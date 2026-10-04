//
//  SwitchManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Foundation
import AppKit
import LaunchAtLogin
import Switches
import Defines

final class SwitchManager: @unchecked Sendable {
    static let shared = SwitchManager()
    
    private var shownSwitchMap = [SwitchType: SwitchProvider?]()
    
    @MainActor var barVMList: [SwitchBarVM] {
        let sortedSwitchMap = shownSwitchMap.sorted() {$0.key.rawValue < $1.key.rawValue}
        var switchBarVMs = [SwitchBarVM]()
        for (_, value) in sortedSwitchMap {
            if let aswitch = value {
                let switchBarVM = SwitchBarVM(switchOperator: aswitch)
                switchBarVMs.append(switchBarVM)
            }
        }
        return switchBarVMs
    }
    
    var shownSwitchCount:Int {
        shownSwitchMap.count
    }
    
    func register(aswitch: SwitchProvider) {
        shownSwitchMap[aswitch.type] = aswitch
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }
    
    func unregister(for type: SwitchType) {
        shownSwitchMap.removeValue(forKey: type)
        shownSwitchMap[type]? = nil
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }
    
    func getSwitch(of type: SwitchType) -> SwitchProvider? {
        return shownSwitchMap[type] ?? nil
    }
    
    func shortcutsBarVMList() -> [ShortcutsBarVM] {
        let shortcuts = Preferences.shared.shortcutsDic
        var list = [ShortcutsBarVM]()
        guard let shortcuts = shortcuts, shortcuts.count > 0 else {
            return list
        }
        
        let sortedDic = shortcuts.sorted{
            return $0.key > $1.key
        }
        
        for (name, toggle) in sortedDic {
            if toggle {
                list.append(ShortcutsBarVM(name: name, iconPNGData: ShortcutAppearanceCache.appearance(named: name)?.iconPNGData))
            }
        }
        
        return list
    }

    @MainActor
    func registerSwitchesShouldShow() {
        let state = getAllSwitchState()
        for index in 0..<switchTypeCount {
            let bitwise:UInt64 = 1 << index
            let shouldShow = (state & bitwise == 0) ? false : true
            if shouldShow {
                let type = SwitchType(rawValue: bitwise)!
                if type == .radioStation {
                    self.register(aswitch: RadioStationSwitch.shared)
                } else {
                    self.register(aswitch: type.getNewSwitchInstance())
                }
                
            }
        }
    }
    
    func getAllSwitchState() -> UInt64 {
        let defaultState: UInt64 = 16_383 // binary 11111111111111
        let storedState = UserDefaults.standard.string(forKey: UserDefaults.Key.SwitchState)
        var state = storedState.flatMap(UInt64.init) ?? defaultState

        // Make the new built-in switch discoverable once without re-enabling it after a user
        // later hides it from Customize.
        if !UserDefaults.standard.bool(forKey: UserDefaults.Key.didInstallCodexUsageSwitch) {
            state |= SwitchType.codexUsage.rawValue
            UserDefaults.standard.set(true, forKey: UserDefaults.Key.didInstallCodexUsageSwitch)
        }

        if !UserDefaults.standard.bool(forKey: UserDefaults.Key.didInstallReverseScrollDirectionSwitch) {
            state |= SwitchType.reverseScrollDirection.rawValue
            UserDefaults.standard.set(true, forKey: UserDefaults.Key.didInstallReverseScrollDirectionSwitch)
        }

        if storedState == nil || state != UInt64(storedState ?? "") {
            UserDefaults.standard.set(String(state), forKey: UserDefaults.Key.SwitchState)
            UserDefaults.standard.synchronize()
        }

        return state
    }

    func activeEvolutionList() -> [EvolutionBarVM] {
        guard let evolutionIDs = UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] else {
            UserDefaults.standard.setValue([String](), forKey: UserDefaults.Key.evolutionIDs)
            return []
        }

        let bars:[EvolutionBarVM?] = evolutionIDs.map {
            guard
                let id = UUID(uuidString: $0),
                let entity = try? EvolutionCommandEntity.fetchRequest(by: id),
                let item = EvolutionAdapter.toEvolutionItem(entity)
            else {
                return nil
            }

            return EvolutionBarVM(evolutionItem: item)
        }

        return bars.compactMap{$0}
    }
}
