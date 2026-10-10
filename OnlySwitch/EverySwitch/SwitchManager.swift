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
        let sortedSwitchMap = shownSwitchMap.sorted() {
            $0.key.legacyIdentifier < $1.key.legacyIdentifier
        }
        var switchBarVMs = [SwitchBarVM]()
        for (_, value) in sortedSwitchMap {
            if let aswitch = value {
                let switchBarVM = SwitchBarVM(switchOperator: aswitch)
                switchBarVMs.append(switchBarVM)
            }
        }
        return switchBarVMs
    }
    
    var shownPersistentSwitchCount: Int {
        shownSwitchMap.keys.filter(\.persistsVisibility).count
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
        let visibleTypes = visibleSwitchTypes()
        for type in SwitchType.allCases
        where type.persistsVisibility == false || visibleTypes.contains(type) {
            register(type: type)
        }
    }

    func visibleSwitchTypes() -> Set<SwitchType> {
        visibleTypesIncludingNewDiscoveries()
    }

    func isVisible(_ type: SwitchType) -> Bool {
        type.persistsVisibility == false || visibleSwitchTypes().contains(type)
    }

    @MainActor
    func setVisible(_ isVisible: Bool, for type: SwitchType) {
        guard type.persistsVisibility else { return }

        if isVisible {
            register(type: type)
        } else {
            if type == .radioStation {
                RadioStationSwitch.shared.playerItem.isPlaying = false
            }
            unregister(for: type)
        }
        SwitchVisibilityState.setVisible(type, for: isVisible, in: .standard)
    }

    @MainActor
    private func register(type: SwitchType) {
        if type == .radioStation {
            register(aswitch: RadioStationSwitch.shared)
        } else {
            register(aswitch: type.getNewSwitchInstance())
        }
    }

    private func visibleTypesIncludingNewDiscoveries() -> Set<SwitchType> {
        var visibleTypes = SwitchVisibilityState.visibleTypes(from: .standard)
        var discoveredTypes = Set<SwitchType>()

        if !UserDefaults.standard.bool(forKey: UserDefaults.Key.didInstallCodexUsageSwitch) {
            discoveredTypes.insert(.codexUsage)
        }
        if !UserDefaults.standard.bool(forKey: UserDefaults.Key.didInstallReverseScrollDirectionSwitch) {
            discoveredTypes.insert(.reverseScrollDirection)
        }

        guard discoveredTypes.isEmpty == false else { return visibleTypes }

        visibleTypes.formUnion(discoveredTypes)
        SwitchVisibilityState.setVisibleTypes(visibleTypes, in: .standard)
        if discoveredTypes.contains(.codexUsage) {
            UserDefaults.standard.set(true, forKey: UserDefaults.Key.didInstallCodexUsageSwitch)
        }
        if discoveredTypes.contains(.reverseScrollDirection) {
            UserDefaults.standard.set(true, forKey: UserDefaults.Key.didInstallReverseScrollDirectionSwitch)
        }
        return visibleTypes
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
