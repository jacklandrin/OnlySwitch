//
//  SwitchType+Instance.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/18.
//

import AppKit
import Defines
import Switches
import Tailscale

extension SwitchType {
    @MainActor
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
        case .aiCommender:
            return AICommanderSwitch.shared
        case .authenticator:
            return AuthenticatorSwitch.shared
        case .soundMixer:
            return SoundMixerSwitch.shared
        case .desktopPet:
            return DesktopPetSwitch()
        case .claudeUsage:
            return ClaudeUsageSwitch()
        case .codexUsage:
            return CodexUsageSwitch()
        case .reverseScrollDirection:
            return ReverseScrollDirectionSwitch()
        case .systemMonitor:
            return SystemMonitorSwitch()
        case .xcodeCleaner:
            return XcodeCleanerSwitch()
        case .appUninstaller:
            return AppUninstallerSwitch()
        case .aphrodite:
            return AphroditeSwitch()
        case .dockPreview:
            return DockPreviewSwitch()
        case .tailscale:
            return TailscaleSwitch()
        }
    }
    
    @MainActor
    func doSwitch() {
        Task { @MainActor in
            let switchOperator = getNewSwitchInstance()
            if self == .tailscale {
                do {
                    let isOn = await switchOperator.currentStatus()
                    try await switchOperator.operateSwitch(isOn: !isOn)
                } catch {
                    SettingsVM.shared.selection = .Tailscale
                    SettingsVM.shared.tailscaleStore.send(.externalFailure(TailscaleError.sanitized(error)))
                    OpenWindows.Setting.open()
                }
                return
            }
            let controlType = barInfo().controlType
            if controlType == .Switch || controlType == .Player {
                let status = await switchOperator.currentStatus()
                _ = try? await switchOperator.operateSwitch(isOn: !status)
                NotificationCenter.default.post(name: .changeSettings, object: nil)
                if controlType == .Switch {
                    _ = try? await displayNotificationCMD(title: barInfo().title.localized(),
                                                          content: "",
                                                          subtitle: status ? "Turn off1".localized() : "Turn on1".localized())
                    .runAppleScript()
                }
            } else if controlType == .Button {
                _ = try? await switchOperator.operateSwitch(isOn: true)
                NotificationCenter.default.post(name: .changeSettings, object: nil)
                _ = try? await displayNotificationCMD(title: barInfo().title.localized(),
                                                      content: "",
                                                      subtitle: "Running".localized())
                .runAppleScript()
            }
        }
    }
}
