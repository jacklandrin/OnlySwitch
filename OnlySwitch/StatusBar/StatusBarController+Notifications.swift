//
//  StatusBarController+Notifications.swift
//  OnlySwitch
//

import AppKit
import Defines
import SystemMonitor

extension StatusBarController {
    func observeNotifications() {
        systemMonitorPreferencesObserver = NotificationCenter.default.addObserver(
            forName: .systemMonitorPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let preferences = notification.object as? SystemMonitorPreferences else { return }
            Task { @MainActor [weak self] in
                self?.systemMonitorStatusItems.apply(preferences)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .changeMenuBarIcon,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            let newImageName = notify.object as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let newImageName else {
                    print("⚠️ Invalid object type for changeMenuBarIcon notification")
                    return
                }
                self.setMainItemButton(image: newImageName)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .togglePopover,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            Task { @MainActor in
                guard let self else {return}
                self.togglePopover(sender: nil)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .shouldHidePopover,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            Task {
                guard let self else {
                    return
                }
                await self.handleHidePopover()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .revealScreenshotsSection,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.revealScreenshotsHost()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .menubarCollapsable,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            let enable = notify.object as? Bool
            Task { @MainActor [weak self] in
                guard let self, let enable else { return }
                if enable {
                    self.setMarkButton()
                    try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                } else if let markItem = self.markItem {
                    try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                    // macOS 26 Tahoe: Safely remove status item
                    NSStatusBar.system.removeStatusItem(markItem)
                    self.markItem = nil
                    print("✅ Mark button removed successfully")
                }
            }
        }
    }

    @MainActor
    private func handleHidePopover() {
        if let statusBarButton = mainItem.button {
            hidePopover(statusBarButton)
        }
    }
}
