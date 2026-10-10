//
//  SwitchVisibilityState.swift
//  OnlySwitch
//

import CoreFoundation
import Foundation
import Extensions

public enum SwitchVisibilityState {
    public enum LoadResult: Equatable, Sendable {
        case missing(Set<SwitchType>)
        case decoded(Set<SwitchType>)
        case unreadable

        public var visibleTypes: Set<SwitchType>? {
            switch self {
            case let .missing(types), let .decoded(types):
                types
            case .unreadable:
                nil
            }
        }
    }

    private static let historicalDefaultMask: UInt64 = 16_383

    // Only types that were assigned a bit in the legacy UInt64 mask belong here.
    // Future identifiers do not need to be bit values and must not be decoded as mask bits.
    private static let legacyBitTypes: [SwitchType] = [
        .hiddeDesktop,
        .darkMode,
        .topNotch,
        .mute,
        .keepAwake,
        .screenSaver,
        .nightShift,
        .autohideDock,
        .autohideMenuBar,
        .airPods,
        .bluetooth,
        .xcodeCache,
        .hiddenFiles,
        .radioStation,
        .emptyTrash,
        .emptyPasteboard,
        .showUserLibrary,
        .showExtensionName,
        .pomodoroTimer,
        .smallLaunchpadIcon,
        .lowpowerMode,
        .muteMicrophone,
        .showFinderPathbar,
        .dockRecent,
        .spotify,
        .applemusic,
        .screenTest,
        .hideMenubarIcons,
        .fkey,
        .backNoises,
        .dimScreen,
        .ejectDiscs,
        .hideWindows,
        .trueTone,
        .topSticker,
        .keyLight,
        .aiCommender,
        .authenticator,
        .soundMixer,
        .desktopPet,
        .codexUsage,
        .reverseScrollDirection,
    ]

    public static func visibleTypes(from defaults: UserDefaults) -> Set<SwitchType> {
        load(from: defaults).visibleTypes ?? []
    }

    public static func load(from defaults: UserDefaults) -> LoadResult {
        let key = UserDefaults.Key.SwitchState
        guard let storedValue = defaults.object(forKey: key) else {
            let visibleTypes = types(in: historicalDefaultMask)
            defaults.set(canonicalIdentifiers(for: visibleTypes), forKey: key)
            return .missing(visibleTypes)
        }

        let visibleTypes: Set<SwitchType>
        if let identifiers = storedValue as? [String] {
            visibleTypes = Set(identifiers.compactMap(SwitchType.init(rawValue:)))
        } else if let storedMask = storedValue as? String, let mask = UInt64(storedMask) {
            visibleTypes = types(in: mask)
        } else if let number = storedValue as? NSNumber, let mask = legacyMask(from: number) {
            visibleTypes = types(in: mask)
        } else {
            // An existing value represents user data, even when this version cannot decode it.
            // Keep it untouched so a future version or restored backup can still recover it.
            return .unreadable
        }

        defaults.set(canonicalIdentifiers(for: visibleTypes), forKey: key)
        return .decoded(visibleTypes)
    }

    public static func isVisible(_ type: SwitchType, in defaults: UserDefaults) -> Bool {
        visibleTypes(from: defaults).contains(type)
    }

    public static func setVisible(
        _ type: SwitchType,
        for isVisible: Bool,
        in defaults: UserDefaults
    ) {
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

    private static func types(in mask: UInt64) -> Set<SwitchType> {
        Set(
            legacyBitTypes.filter {
                mask & $0.legacyIdentifier != 0
            }
        )
    }

    private static func legacyMask(from number: NSNumber) -> UInt64? {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return UInt64(number.stringValue)
    }

    private static func canonicalIdentifiers(for types: Set<SwitchType>) -> [String] {
        types
            .sorted { $0.legacyIdentifier < $1.legacyIdentifier }
            .map(\.rawValue)
    }
}
