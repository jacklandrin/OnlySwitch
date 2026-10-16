//
//  BuiltInSwitchCatalog.swift
//  OnlySwitch
//

import Extensions
import Foundation
import Switches

enum BuiltInSwitchSection: CaseIterable, Identifiable, Sendable {
    case audio
    case displayAndAppearance
    case desktopAndFinder
    case cleanupAndStorage
    case productivityAndTools
    case other

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .audio:
            "Audio"
        case .displayAndAppearance:
            "Display & Appearance"
        case .desktopAndFinder:
            "Desktop & Finder"
        case .cleanupAndStorage:
            "Cleanup & Storage"
        case .productivityAndTools:
            "Productivity & Tools"
        case .other:
            "Other"
        }
    }

    func contains(_ type: SwitchType) -> Bool {
        BuiltInSwitchCatalog.section(for: type) == self
    }
}

enum BuiltInSwitchCatalog {
    typealias Localize = (_ key: String) -> String

    static func section(for type: SwitchType) -> BuiltInSwitchSection {
        switch type {
        case .mute, .muteMicrophone, .airPods, .radioStation, .spotify,
             .applemusic, .backNoises, .soundMixer:
            .audio

        case .darkMode, .topNotch, .screenSaver, .nightShift, .screenTest,
             .dimScreen, .trueTone, .keyLight:
            .displayAndAppearance

        case .hiddeDesktop, .autohideDock, .autohideMenuBar, .hiddenFiles,
             .showUserLibrary, .showExtensionName, .smallLaunchpadIcon,
             .showFinderPathbar, .dockRecent, .hideMenubarIcons, .hideWindows,
             .topSticker, .desktopPet, .reverseScrollDirection, .dockPreview:
            .desktopAndFinder

        case .xcodeCache, .emptyTrash, .emptyPasteboard, .ejectDiscs:
            .cleanupAndStorage

        case .keepAwake, .bluetooth, .pomodoroTimer, .lowpowerMode, .fkey,
             .aiCommender, .authenticator, .codexUsage, .systemMonitor,
             .aphrodite:
            .productivityAndTools

        @unknown default:
            .other
        }
    }

    static func sectioned(types: [SwitchType])
        -> [(section: BuiltInSwitchSection, types: [SwitchType])]
    {
        BuiltInSwitchSection.allCases.compactMap { section in
            let matchingTypes = types.filter(section.contains)
            return matchingTypes.isEmpty ? nil : (section, matchingTypes)
        }
    }

    @MainActor
    static func sections(
        items: [CustomizeItem],
        matching query: String,
        locale: Locale = .current,
        localize: Localize = { $0.localized() }
    ) -> [(section: BuiltInSwitchSection, items: [CustomizeItem])] {
        BuiltInSwitchSection.allCases.compactMap { section in
            let sectionMatches = matches(
                sourceTitle: section.titleKey,
                query: query,
                locale: locale,
                localize: localize
            )
            let matchingItems = items.filter { item in
                section.contains(item.type)
                    && (sectionMatches || matches(
                        sourceTitle: item.barInfo.title,
                        query: query,
                        locale: locale,
                        localize: localize
                    ))
            }
            return matchingItems.isEmpty ? nil : (section, matchingItems)
        }
    }

    @MainActor
    static func matches(
        _ item: CustomizeItem,
        query: String,
        locale: Locale = .current,
        localize: Localize = { $0.localized() }
    ) -> Bool {
        matches(
            sourceTitle: item.barInfo.title,
            query: query,
            locale: locale,
            localize: localize
        )
    }

    static func matches(
        sourceTitle: String,
        query: String,
        locale: Locale = .current,
        localize: Localize = { $0.localized() }
    ) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return true }

        return [localize(sourceTitle), sourceTitle].contains { candidate in
            candidate.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            ) != nil
        }
    }
}
