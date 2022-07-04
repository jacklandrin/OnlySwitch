//
//  SwitchType+Instance.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/18.
//

import Foundation
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
        }
    }
}
