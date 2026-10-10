//
//  SwitchVisibilityState.swift
//  OnlySwitch
//

import Foundation
import Extensions

public enum SwitchVisibilityState {
    private static let historicalDefaultMask: UInt64 = 16_383

    public static func visibleTypes(from defaults: UserDefaults) -> Set<SwitchType> {
        let visibleTypes: Set<SwitchType>

        if let identifiers = defaults.object(forKey: UserDefaults.Key.SwitchState) as? [String] {
            visibleTypes = Set(
                identifiers.compactMap(SwitchType.init(rawValue:)).filter(\.persistsVisibility)
            )
        } else if
            let storedMask = defaults.string(forKey: UserDefaults.Key.SwitchState),
            let mask = UInt64(storedMask)
        {
            visibleTypes = persistentTypes(in: mask)
        } else {
            visibleTypes = persistentTypes(in: historicalDefaultMask)
        }

        defaults.set(canonicalIdentifiers(for: visibleTypes), forKey: UserDefaults.Key.SwitchState)
        return visibleTypes
    }

    public static func isVisible(_ type: SwitchType, in defaults: UserDefaults) -> Bool {
        type.persistsVisibility == false || visibleTypes(from: defaults).contains(type)
    }

    public static func setVisible(
        _ type: SwitchType,
        for isVisible: Bool,
        in defaults: UserDefaults
    ) {
        guard type.persistsVisibility else { return }

        var visibleTypes = visibleTypes(from: defaults)
        if isVisible {
            visibleTypes.insert(type)
        } else {
            visibleTypes.remove(type)
        }
        defaults.set(canonicalIdentifiers(for: visibleTypes), forKey: UserDefaults.Key.SwitchState)
    }

    public static func setVisibleTypes(_ types: Set<SwitchType>, in defaults: UserDefaults) {
        defaults.set(canonicalIdentifiers(for: types), forKey: UserDefaults.Key.SwitchState)
    }

    private static func persistentTypes(in mask: UInt64) -> Set<SwitchType> {
        Set(
            SwitchType.allCases.filter {
                $0.persistsVisibility && mask & $0.legacyIdentifier != 0
            }
        )
    }

    private static func canonicalIdentifiers(for types: Set<SwitchType>) -> [String] {
        types
            .filter(\.persistsVisibility)
            .sorted { $0.legacyIdentifier < $1.legacyIdentifier }
            .map(\.rawValue)
    }
}
