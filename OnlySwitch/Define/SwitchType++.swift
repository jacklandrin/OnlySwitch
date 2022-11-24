//
//  SwitchType+Instance.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/18.
//

import AppKit
extension SwitchType {
    func getNewSwitchInstance() -> SwitchProvider {
        switch self {
        case .hiddeDesktop:
            return HiddenDesktopSwitch()
        case .darkMode:
            return DarkModeSwitch()
        case .topNotch:
            return TopNotchSwitch()
        case .mute:
            return MuteSwitch()
        case .keepAwake:
            return KeepAwakeSwitch.shared
        case .screenSaver:
            return ScreenSaverSwitch()
        case .nightShift:
            return NightShiftSwitch()
        case .autohideDock:
            return AutohideDockSwitch()
        case .autohideMenuBar:
            return AutohideMenuBarSwitch()
        case .airPods:
            return AirPodsSwitch()
        case .bluetooth:
            return BluetoothSwitch()
        case .xcodeCache:
            return XcodeCacheSwitch()
        case .hiddenFiles:
            return HiddenFilesSwitch()
        case .radioStation:
            return RadioStationSwitch.shared
        case .emptyTrash:
            return EmptyTrashSwitch()
        case .emptyPasteboard:
            return EmptyPasteboardSwitch()
        case .showUserLibrary:
            return ShowUserLibrarySwitch()
        case .showExtensionName:
            return ShowExtensionNameSwitch()
        case .pomodoroTimer:
            return PomodoroTimerSwitch.shared
        case .smallLaunchpadIcon:
            return SmallLaunchpadIconSwitch()
        case .lowpowerMode:
            return LowPowerModeSwitch()
        case .muteMicrophone:
            return MuteMicSwitch()
        case .showFinderPathbar:
            return ShowFinderPathbarSwitch()
        case .dockRecent:
            return DockRecentSwitch()
        case .spotify:
            return SpotifySwitch.shared
        case .applemusic:
            return AppleMusicSwitch.shared
        case .screenTest:
            return ScreenTestSwitch.shared
        case .hideMenubarIcons:
            return HideMenubarIconsSwitch.shared
        case .fkey:
            return FKeySwitch.shared
        case .backNoises:
            return BackNoisesSwitch()
        case .dimScreen:
            return DimScreenSwitch()
        case .ejectDiscs:
            return EjectDiscsSWitch()
        }
    }
    
    func barInfo() -> SwitchBarInfo {
        switch self {
        case .hiddeDesktop:
            return SwitchBarInfo(title:"Hide Desktop",
                                 onImage:NSImage(named: "desktopcomputer"),
                                 offImage:NSImage(named: "desktop_with_icon"))
        case .darkMode:
            return SwitchBarInfo(title:"Dark Mode",
                                 onImage:NSImage(named: "darkmode_on"),
                                 offImage: NSImage(named: "darkmode_off"))
        case .topNotch:
            return SwitchBarInfo(title:"Hide Notch",
                                 onImage:NSImage(named:"laptopnotchhidden"),
                                 offImage: NSImage(named: "laptopwithnotch"))
        case .mute:
            return SwitchBarInfo(title: "Mute",
                                 onImage: NSImage(systemSymbolName: "speaker.slash.circle"),
                                 offImage: NSImage(systemSymbolName: "speaker.wave.2.circle"),
                                 category: .audio)
        case .keepAwake:
            return SwitchBarInfo(title: "Keep Awake",
                                onImage: NSImage(systemSymbolName: "lock.slash.fill"),
                                offImage: NSImage(systemSymbolName: "lock.slash"))
        case .screenSaver:
            return SwitchBarInfo(title: "Screen Saver",
                                 onImage: NSImage(systemSymbolName: "display"),
                                 offImage: NSImage(systemSymbolName: "display"))
        case .nightShift:
            return SwitchBarInfo(title: "Night Shift",
                                 onImage: NSImage(systemSymbolName: "moon.stars.fill"),
                                 offImage: NSImage(systemSymbolName: "moon.stars"))
        case .autohideDock:
            return SwitchBarInfo(title: "Autohide Dock",
                                 onImage: NSImage(systemSymbolName: "dock.arrow.down.rectangle"),
                                 offImage: NSImage(systemSymbolName: "dock.rectangle"))
        case .autohideMenuBar:
            return SwitchBarInfo(title: "Autohide Menu Bar",
                                 onImage: NSImage(systemSymbolName: "menubar.arrow.up.rectangle"),
                                 offImage: NSImage(systemSymbolName: "menubar.rectangle"))
        case .airPods:
            return SwitchBarInfo(title: "AirPods",
                                 onImage: NSImage(systemSymbolName: "airpodspro"),
                                 offImage: NSImage(systemSymbolName: "airpodspro"),
                                 category: .audio)
        case .bluetooth:
            return SwitchBarInfo(title: "Bluetooth",
                                 onImage: NSImage(named: "bluetooth_on"),
                                 offImage: NSImage(named: "bluetooth_off"))
        case .xcodeCache:
            return SwitchBarInfo(title: "Xcode Derived Data",
                                 onImage: NSImage(systemSymbolName: "hammer.circle.fill"),
                                 offImage: NSImage(systemSymbolName: "hammer.circle"),
                                 controlType: .Button,
                                 category: .cleanup)
        case .hiddenFiles:
            return SwitchBarInfo(title: "Show Hidden Files",
                                 onImage: NSImage(systemSymbolName: "eye"),
                                 offImage: NSImage(systemSymbolName: "eye.slash"))
        case .radioStation:
            return SwitchBarInfo(title: "Radio Player",
                                 onImage: NSImage(systemSymbolName: "radio"),
                                 offImage: NSImage(systemSymbolName: "radio"),
                                 controlType: .Player,
                                 category: .audio)
        case .emptyTrash:
            return SwitchBarInfo(title: "Empty Trash",
                                 onImage: NSImage(systemSymbolName: "trash"),
                                 offImage: NSImage(systemSymbolName: "trash"),
                                 controlType: .Button,
                                 category: .cleanup)
        case .emptyPasteboard:
            return SwitchBarInfo(title: "Empty Pasteboard",
                                 onImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                                 offImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                                 controlType: .Button,
                                 category: .cleanup)
        case .showUserLibrary:
            return SwitchBarInfo(title: "Show User Library",
                                 onImage: NSImage(systemSymbolName: "building.columns.fill"),
                                 offImage: NSImage(systemSymbolName: "building.columns"))
        case .showExtensionName:
            return SwitchBarInfo(title: "Show Extension Name",
                                 onImage: NSImage(named: "extension_on"),
                                 offImage: NSImage(named: "extension_off"))
        case .pomodoroTimer:
            return SwitchBarInfo(title: "Pomodoro Timer",
                                 onImage: NSImage(systemSymbolName: "timer"),
                                 offImage: NSImage(systemSymbolName: "timer"))
        case .smallLaunchpadIcon:
            return SwitchBarInfo(title: "Small Launchpad Icon",
                                 onImage: NSImage(systemSymbolName: "square.grid.4x3.fill"),
                                 offImage: NSImage(systemSymbolName: "square.grid.4x3.fill"))
        case .lowpowerMode:
            return SwitchBarInfo(title: "Low Power Mode",
                                 onImage: NSImage(systemSymbolName: "bolt.circle"),
                                 offImage: NSImage(systemSymbolName: "bolt.circle.fill"))
        case .muteMicrophone:
            return SwitchBarInfo(title: "Mute Mic",
                                 onImage: NSImage(systemSymbolName: "mic.slash.circle"),
                                 offImage: NSImage(systemSymbolName: "mic.circle"),
                                 category: .audio)
        case .showFinderPathbar:
            return SwitchBarInfo(title: "Show Finder Path Bar",
                                 onImage: NSImage(systemSymbolName: "greaterthan.square.fill"),
                                 offImage: NSImage(systemSymbolName: "greaterthan.square"))
        case .dockRecent:
            return SwitchBarInfo(title: "Recent Apps in Dock",
                                 onImage: NSImage(named: "dock_recent_on"),
                                 offImage: NSImage(named: "dock_recent_off"))
        case .spotify:
            return SwitchBarInfo(title: "Spotify",
                                 onImage: NSImage(named: "spotify_icon"),
                                 offImage: NSImage(named: "spotify_icon"),
                                 controlType: .Player,
                                 category: .audio)
        case .applemusic:
            return SwitchBarInfo(title: "Apple Music",
                                 onImage: NSImage(named: "apple_music_icon"),
                                 offImage: NSImage(named: "apple_music_icon"),
                                 controlType: .Player,
                                 category: .audio)
        case .screenTest:
            return SwitchBarInfo(title: "Screen Test",
                                 onImage: NSImage(systemSymbolName: "display.trianglebadge.exclamationmark"),
                                 offImage: NSImage(systemSymbolName: "display.trianglebadge.exclamationmark"),
                                 controlType: .Button,
                                 category: .tool)
        case .hideMenubarIcons:
            return SwitchBarInfo(title: "Hide Menu Bar Icons",
                                 onImage: NSImage(named: "mark_icon"),
                                 offImage: NSImage(named: "mark_icon_off"))
        case .fkey:
            return SwitchBarInfo(title: "FKey",
                                 onImage: NSImage(systemSymbolName: "fn"),
                                 offImage: NSImage(systemSymbolName: "sun.max"))
        case .backNoises:
            return SwitchBarInfo(title: "Back Noises",
                                 onImage: NSImage(systemSymbolName: "ear.and.waveform"),
                                 offImage: NSImage(systemSymbolName: "ear"),
                                 controlType: .Player,
                                 category: .audio)
        case .dimScreen:
            return SwitchBarInfo(title: "Dim Screen",
                                 onImage: NSImage(systemSymbolName: "sun.min.fill"),
                                 offImage: NSImage(systemSymbolName: "sun.max.fill"))
        case .ejectDiscs:
            return SwitchBarInfo(title: "Eject Discs",
                                 onImage: NSImage(systemSymbolName: "eject.circle"),
                                 offImage: NSImage(systemSymbolName: "eject.circle"),
                                 controlType: .Button,
                                 category: .tool)
        }
    }

}
