//
//  SwitchType+Instance.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/18.
//

import AppKit
import Defines
import Switches

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
            case .hideWindows:
                return HideWindowsSwitch()
            case .trueTone:
                return TrueToneSwitch()
            case .topSticker:
                return TopStickerSwitch.shared
            case .keyLight:
                return KeyLightSwitch.shared
        }
    }
    
    func doSwitch() {
        let switchOperator = getNewSwitchInstance()
        let controlType = barInfo().controlType
        if controlType == .Switch || controlType == .Player {
            let status = switchOperator.currentStatus()
            Task {
                do {
                    _ = try await switchOperator.operateSwitch(isOn: !status)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                        if controlType == .Switch {
                            _ = try? displayNotificationCMD(title: barInfo().title.localized(),
                                                            content: "",
                                                            subtitle: status ? "Turn off1".localized() : "Turn on1".localized())
                            .runAppleScript()
                        }
                    }
                } catch {

                }
            }
        } else if controlType == .Button {
            Task {
                do {
                    _ = try await switchOperator.operateSwitch(isOn: true)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                        _ = try? displayNotificationCMD(title: barInfo().title.localized(),
                                                        content: "",
                                                        subtitle: "Running".localized())
                        .runAppleScript()
                    }
                } catch {

                }

            }
        }

    }
}
