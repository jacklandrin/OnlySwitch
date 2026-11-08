//
//  SwitchType+BarInfo.swift
//  OnlySwitch
//

import AppKit

extension SwitchType {
    public func barInfo() -> SwitchBarInfo {
        switch self {
        case .hiddeDesktop:
            return SwitchBarInfo(
                title:"Hide Desktop",
                onImage:NSImage(named: "desktopcomputer"),
                offImage:NSImage(named: "desktop_with_icon")
            )
        case .darkMode:
            return SwitchBarInfo(
                title:"Dark Mode",
                onImage:NSImage(named: "darkmode_on"),
                offImage: NSImage(named: "darkmode_off")
            )
        case .topNotch:
            return SwitchBarInfo(
                title:"Hide Notch",
                onImage:NSImage(named:"laptopnotchhidden"),
                offImage: NSImage(named: "laptopwithnotch")
            )
        case .mute:
            return SwitchBarInfo(
                title: "Mute",
                onImage: NSImage(systemSymbolName: "speaker.slash.circle"),
                offImage: NSImage(systemSymbolName: "speaker.wave.2.circle"),
                category: .audio
            )
        case .keepAwake:
            return SwitchBarInfo(
                title: "Keep Awake",
                onImage: NSImage(systemSymbolName: "lock.slash.fill"),
                offImage: NSImage(systemSymbolName: "lock.slash")
            )
        case .screenSaver:
            return SwitchBarInfo(
                title: "Screen Saver",
                onImage: NSImage(systemSymbolName: "display"),
                offImage: NSImage(systemSymbolName: "display")
            )
        case .nightShift:
            return SwitchBarInfo(
                title: "Night Shift",
                onImage: NSImage(systemSymbolName: "moon.stars.fill"),
                offImage: NSImage(systemSymbolName: "moon.stars")
            )
        case .autohideDock:
            return SwitchBarInfo(
                title: "Autohide Dock",
                onImage: NSImage(systemSymbolName: "dock.arrow.down.rectangle"),
                offImage: NSImage(systemSymbolName: "dock.rectangle")
            )
        case .autohideMenuBar:
            return SwitchBarInfo(
                title: "Autohide Menu Bar",
                onImage: NSImage(systemSymbolName: "menubar.arrow.up.rectangle"),
                offImage: NSImage(systemSymbolName: "menubar.rectangle")
            )
        case .airPods:
            return SwitchBarInfo(
                title: "AirPods",
                onImage: NSImage(systemSymbolName: "airpodspro"),
                offImage: NSImage(systemSymbolName: "airpodspro"),
                category: .audio
            )
        case .bluetooth:
            return SwitchBarInfo(
                title: "Bluetooth",
                onImage: NSImage(named: "bluetooth_on"),
                offImage: NSImage(named: "bluetooth_off")
            )
        case .xcodeCache:
            return SwitchBarInfo(
                title: "Xcode Derived Data",
                onImage: NSImage(systemSymbolName: "hammer.circle.fill"),
                offImage: NSImage(systemSymbolName: "hammer.circle"),
                controlType: .Button,
                category: .cleanup
            )
        case .hiddenFiles:
            return SwitchBarInfo(
                title: "Show Hidden Files",
                onImage: NSImage(systemSymbolName: "eye"),
                offImage: NSImage(systemSymbolName: "eye.slash")
            )
        case .radioStation:
            return SwitchBarInfo(
                title: "Radio Player",
                onImage: NSImage(systemSymbolName: "radio"),
                offImage: NSImage(systemSymbolName: "radio"),
                controlType: .Player,
                category: .audio
            )
        case .emptyTrash:
            return SwitchBarInfo(
                title: "Empty Trash",
                onImage: NSImage(systemSymbolName: "trash"),
                offImage: NSImage(systemSymbolName: "trash"),
                controlType: .Button,
                category: .cleanup
            )
        case .emptyPasteboard:
            return SwitchBarInfo(
                title: "Empty Pasteboard",
                onImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                offImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                controlType: .Button,
                category: .cleanup
            )
        case .showUserLibrary:
            return SwitchBarInfo(
                title: "Show User Library",
                onImage: NSImage(systemSymbolName: "building.columns.fill"),
                offImage: NSImage(systemSymbolName: "building.columns")
            )
        case .showExtensionName:
            return SwitchBarInfo(
                title: "Show Extension Name",
                onImage: NSImage(named: "extension_on"),
                offImage: NSImage(named: "extension_off")
            )
        case .pomodoroTimer:
            return SwitchBarInfo(
                title: "Pomodoro Timer",
                onImage: NSImage(systemSymbolName: "timer"),
                offImage: NSImage(systemSymbolName: "timer")
            )
        case .smallLaunchpadIcon:
            return SwitchBarInfo(
                title: "Small Launchpad Icon",
                onImage: NSImage(systemSymbolName: "square.grid.4x3.fill"),
                offImage: NSImage(systemSymbolName: "square.grid.4x3.fill")
            )
        case .lowpowerMode:
            return SwitchBarInfo(
                title: "Low Power Mode",
                onImage: NSImage(systemSymbolName: "bolt.circle"),
                offImage: NSImage(systemSymbolName: "bolt.circle.fill")
            )
        case .muteMicrophone:
            return SwitchBarInfo(
                title: "Mute Mic",
                onImage: NSImage(systemSymbolName: "mic.slash.circle"),
                offImage: NSImage(systemSymbolName: "mic.circle"),
                category: .audio
            )
        case .showFinderPathbar:
            return SwitchBarInfo(
                title: "Show Finder Path Bar",
                onImage: NSImage(systemSymbolName: "greaterthan.square.fill"),
                offImage: NSImage(systemSymbolName: "greaterthan.square")
            )
        case .dockRecent:
            return SwitchBarInfo(
                title: "Recent Apps in Dock",
                onImage: NSImage(named: "dock_recent_on"),
                offImage: NSImage(named: "dock_recent_off")
            )
        case .spotify:
            return SwitchBarInfo(
                title: "Spotify",
                onImage: NSImage(named: "spotify_icon"),
                offImage: NSImage(named: "spotify_icon"),
                controlType: .Player,
                category: .audio
            )
        case .applemusic:
            return SwitchBarInfo(
                title: "Apple Music",
                onImage: NSImage(named: "apple_music_icon"),
                offImage: NSImage(named: "apple_music_icon"),
                controlType: .Player,
                category: .audio
            )
        case .screenTest:
            return SwitchBarInfo(
                title: "Screen Test",
                onImage: NSImage(systemSymbolName: "display.trianglebadge.exclamationmark"),
                offImage: NSImage(systemSymbolName: "display.trianglebadge.exclamationmark"),
                controlType: .Button,
                category: .tool
            )
        case .hideMenubarIcons:
            return SwitchBarInfo(
                title: "Hide Menu Bar Icons",
                onImage: NSImage(named: "mark_icon"),
                offImage: NSImage(named: "mark_icon_off")
            )
        case .fkey:
            return SwitchBarInfo(
                title: "FKey",
                onImage: NSImage(systemSymbolName: "fn"),
                offImage: NSImage(systemSymbolName: "sun.max")
            )
        case .backNoises:
            return SwitchBarInfo(
                title: "Back Noises",
                onImage: NSImage(systemSymbolName: "ear.and.waveform"),
                offImage: NSImage(systemSymbolName: "ear"),
                controlType: .Player,
                category: .audio
            )
        case .dimScreen:
            return SwitchBarInfo(
                title: "Dim Screen",
                onImage: NSImage(systemSymbolName: "sun.min.fill"),
                offImage: NSImage(systemSymbolName: "sun.max.fill")
            )
        case .ejectDiscs:
            return SwitchBarInfo(
                title: "Eject Discs",
                onImage: NSImage(systemSymbolName: "eject.circle"),
                offImage: NSImage(systemSymbolName: "eject.circle"),
                controlType: .Button,
                category: .tool
            )
        case .hideWindows:
            return SwitchBarInfo(
                title: "Hide Windows",
                onImage: NSImage(systemSymbolName: "macwindow"),
                offImage: NSImage(systemSymbolName: "macwindow")
            )
        case .trueTone:
            return SwitchBarInfo(
                title: "True Tone",
                onImage: NSImage(named: "truetone"),
                offImage: NSImage(named: "truetone")
            )
        case .topSticker:
            return SwitchBarInfo(
                title: "Top Sticker",
                onImage: NSImage(named: "sticker"),
                offImage: NSImage(named: "sticker"),
                category: .tool
            )
            
        case .keyLight:
            return SwitchBarInfo(
                title: "Key Light",
                onImage: NSImage(systemSymbolName: "light.max"),
                offImage: NSImage(systemSymbolName: "light.min")
            )
            
        case .aiCommender:
            return SwitchBarInfo(
                title: "Only Agent",
                onImage: NSImage(named: "ai_commander"),
                offImage: NSImage(named: "ai_commander"),
                controlType: .Button,
                category: .tool
            )
        case .authenticator:
            return SwitchBarInfo(
                title: "Authenticator",
                onImage: NSImage(systemSymbolName: "key.fill"),
                offImage: NSImage(systemSymbolName: "key"),
                category: .tool
            )
        case .soundMixer:
            return SwitchBarInfo(
                title: "Sound Mixer",
                onImage: NSImage(systemSymbolName: "slider.horizontal.3"),
                offImage: NSImage(systemSymbolName: "slider.horizontal.3"),
                category: .audio
            )
        case .desktopPet:
            return SwitchBarInfo(
                title: "Show Desktop Pet",
                onImage: NSImage(systemSymbolName: "pawprint"),
                offImage: NSImage(systemSymbolName: "pawprint")
            )
        case .dockPreview:
            return SwitchBarInfo(
                title: "Dock Preview",
                onImage: NSImage(systemSymbolName: "dock.rectangle"),
                offImage: NSImage(systemSymbolName: "dock.rectangle")
            )
        case .claudeUsage:
            return SwitchBarInfo(
                title: "Claude Usage",
                onImage: NSImage(named: "claude_logo"),
                offImage: NSImage(named: "claude_logo")
            )
        case .codexUsage:
            return SwitchBarInfo(
                title: "Codex Usage",
                onImage: NSImage(named: "openai_logo"),
                offImage: NSImage(named: "openai_logo"),
                category: .tool
            )
        case .reverseScrollDirection:
            return SwitchBarInfo(
                title: "Natural Scrolling",
                onImage: NSImage(systemSymbolName: "computermouse.fill"),
                offImage: NSImage(systemSymbolName: "computermouse")
            )
        case .systemMonitor:
            return SwitchBarInfo(
                title: "System Monitor",
                onImage: NSImage(systemSymbolName: "waveform.path.ecg"),
                offImage: NSImage(systemSymbolName: "waveform.path.ecg"),
                category: .tool
            )
        case .tailscale:
            return SwitchBarInfo(
                title: "Tailscale",
                onImage: NSImage(systemSymbolName: "network"),
                offImage: NSImage(systemSymbolName: "network"),
                category: .tool
            )
        case .appUninstaller:
            return SwitchBarInfo(
                title: "App Uninstaller",
                onImage: NSImage(systemSymbolName: "trash.fill"),
                offImage: NSImage(systemSymbolName: "trash"),
                category: .cleanup
            )
        case .xcodeCleaner:
            return SwitchBarInfo(
                title: "Xcode Cleaner",
                onImage: NSImage(systemSymbolName: "hammer.fill"),
                offImage: NSImage(systemSymbolName: "hammer"),
                category: .tool
            )
        case .aphrodite:
            return SwitchBarInfo(
                title: "Aphrodite",
                onImage: NSImage(systemSymbolName: "sparkles.rectangle.stack"),
                offImage: NSImage(systemSymbolName: "sparkles.rectangle.stack"),
                category: .tool
            )
        }
    }
}
