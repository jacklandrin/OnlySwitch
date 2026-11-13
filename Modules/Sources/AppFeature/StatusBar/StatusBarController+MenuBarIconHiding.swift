//
//  StatusBarController+MenuBarIconHiding.swift
//  OnlySwitch
//

import AppKit
import Defines

extension StatusBarController {
    func configureMenuBarIconHiding() {
        let legacyApplier = LegacyMarkerVisibilityApplier { [weak self] isCollapsed in
            guard let self else { return }
            self.markItem?.length = isCollapsed ? MarkItemLength.collapse : MarkItemLength.normal
        }
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { [weak self] in self?.screenMidX(of: self?.markItem) },
            mainItemScreenX: { [weak self] in self?.screenMidX(of: self?.mainItem) },
            ownBundleIdentifier: { Bundle.main.bundleIdentifier },
            source: SystemAXMenuBarSource(preferredDisplayBounds: { [weak self] in
                guard let self else { return .null }
                return self.displayBounds(of: self.markItem) ?? .null
            })
        )
        let nativeApplier = MenuBarClientCoreVisibilityApplier(bridge: privateMenuBarBridge)
        nativeVisibilityApplier = nativeApplier
        menuBarIconHidingCoordinator = MenuBarIconHidingCoordinator(
            nativeApplier: nativeApplier,
            legacyApplier: legacyApplier,
            visibleItemResolver: resolver
        )

        let owner = menuBarTransitionOwner
        HideMenubarIconsSwitch.shared.installTransition(owner: owner) { [weak self] isCollapsed in
            guard let self else { throw MenuBarIconHidingError.nativeOperationFailed }
            try await self.menuBarIconHidingCoordinator.setCollapsed(isCollapsed)
        }
    }

    /// The collapse state a click on the marker asks for, or nil when the click changes nothing.
    /// A left click toggles hiding; a right click only hides, as it always has.
    static func markerClickTarget(isRightClick: Bool, isCollapsed: Bool) -> Bool? {
        if isRightClick {
            return isCollapsed ? nil : true
        }
        return !isCollapsed
    }

    private func screenMidX(of item: NSStatusItem?) -> CGFloat? {
        guard let button = item?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    private func displayBounds(of item: NSStatusItem?) -> CGRect? {
        guard let screen = item?.button?.window?.screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    }

    var isMarkItemValidPosition:Bool {
        guard let mainItemX = screenMidX(of: mainItem), mainItemX.isFinite,
              let markItemX = screenMidX(of: markItem), markItemX.isFinite
        else { return false }
        return mainItemX >= markItemX
    }

    func restoreMenuBarIconHidingState() async {
        if isMenubarCollapse {
            for attempt in 0..<10 {
                guard isMarkItemValidPosition == false else { break }
                guard attempt < 9 else {
                    await recoverFromFailedMenuBarStartup()
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }

        do {
            try await HideMenubarIconsSwitch.shared.operateSwitch(isOn: isMenubarCollapse)
        } catch {
            await recoverFromFailedMenuBarStartup()
        }
    }

    private func recoverFromFailedMenuBarStartup() async {
        try? await menuBarIconHidingCoordinator.setCollapsed(false)
        HideMenubarIconsSwitch.shared.resetPersistedStateAfterFailedStartup()
    }
}
