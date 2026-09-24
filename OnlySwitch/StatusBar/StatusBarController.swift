//
//  StatusBarController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit
import CoreGraphics
import Defines
import SwiftUI
import Foundation
import ComposableArchitecture
import SystemMonitor

@MainActor
class StatusBarController {
    struct MarkItemLength {
        static let collapse:CGFloat = 10000
        static let normal:CGFloat = NSStatusItem.squareLength
    }

    @MainActor
    static func configureStatusItem(_ item: NSStatusItem) {
        item.behavior.insert(.removalAllowed)
        item.isVisible = true
    }

    private var mainItem: NSStatusItem
    private var markItem: NSStatusItem?
    private var popover: NSPopover
    private var eventMonitor : EventMonitor?
    private let menuBarTransitionOwner = UUID()
    private let privateMenuBarBridge = MenuBarClientCoreBridgeAdapter()
    private var nativeVisibilityApplier: MenuBarClientCoreVisibilityApplier!
    private var menuBarIconHidingCoordinator: MenuBarIconHidingCoordinator!
    private var systemMonitorStatusItems: SystemMonitorStatusItemController!
    private var systemMonitorPreferencesObserver: NSObjectProtocol?
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    private var isMenubarCollapse:Bool
    private var hasOtherPopover = false

    private var onlyControlWindow: OnlyControlWindow {
        OnlyControlWindow.shared
    }

    var currentMenubarIcon: String {
        Preferences.shared.currentMenubarIcon
    }

    var currentAppearance: SwitchListAppearance {
        SwitchListAppearance(rawValue: Preferences.shared.currentAppearance) ?? .single
    }

    var menubarCollaspable: Bool {
        Preferences.shared.menubarCollaspable
    }

    init(_ popover: NSPopover) {
        self.popover = popover

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        Self.configureStatusItem(mainItem)
        
        // macOS 26 Tahoe: Button might not be immediately available, retry if needed
        setupMainItemButtonWithRetry(image: currentMenubarIcon)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.mouseEventHandler(event)
        }

        configureMenuBarIconHiding()

        HideMenubarIconsSwitch.shared.isButtonPositionValid = {
            var isValid:Bool!
            if Thread.isMainThread {
                isValid = self.isMarkItemValidPosition
            } else {
                DispatchQueue.main.sync {
                    isValid = self.isMarkItemValidPosition
                }
            }
            return isValid
        }

        if menubarCollaspable {
            setMarkButton()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.restoreMenuBarIconHidingState()
            }
        }

        let monitorPreferences = Preferences.shared.systemMonitorPreferences
        systemMonitorStatusItems = SystemMonitorStatusItemController(
            onClick: { [weak self] in
                self?.togglePopover(sender: nil)
            }
        )
        systemMonitorStatusItems.apply(monitorPreferences)

        observeNotifications()
    }

    @objc private func togglePopover(sender:AnyObject?) {
        // Safety check: ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover(sender: sender)
            }
            return
        }
        
        // macOS 26 Tahoe: Validate button still exists before proceeding
        guard mainItem.button != nil else {
            print("⚠️ togglePopover called but status bar button is nil")
            return
        }
        
        // Safety check: ensure currentEvent exists before accessing it
        guard let event = NSApp.currentEvent else {
            // If no current event, treat as left click
            if hasOtherPopover {
                return
            }
            
            let condition = currentAppearance == .onlyControl ? onlyControlWindow.isShowing : popover.isShown
            
            if condition {
                hidePopover(sender)
            } else {
                showPopover(sender)
            }
            return
        }
        
        if event.isRightClicked {
            guard menubarCollaspable else {return}

            Task {
                if isMenubarCollapse {
                    try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                }
            }

        } else {
            if hasOtherPopover {
                return
            }

            let condition = currentAppearance == .onlyControl ? onlyControlWindow.isShowing : popover.isShown

            if(condition) {
                hidePopover(sender)
            } else {
                showPopover(sender)
            }
        }
    }

    @objc private func showMenuBarIcons(sender:AnyObject) {
        // macOS 26 Tahoe: Validate mark button still exists
        guard markItem?.button != nil else {
            print("⚠️ showMenuBarIcons called but mark button is nil")
            return
        }
        
        guard let event = NSApp.currentEvent, event.isRightClicked else {return}
        Task {
            if isMenubarCollapse == false {
                try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: true)
            }
        }
    }

    private func configureMenuBarIconHiding() {
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

    private var isMarkItemValidPosition:Bool {
        guard let mainItemX = screenMidX(of: mainItem), mainItemX.isFinite,
              let markItemX = screenMidX(of: markItem), markItemX.isFinite
        else { return false }
        return mainItemX >= markItemX
    }

    private func restoreMenuBarIconHidingState() async {
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

    /// Setup main item button with retry mechanism for macOS 26 compatibility
    private func setupMainItemButtonWithRetry(image: String, attempt: Int = 0) {
        guard let mainItemButton = mainItem.button else {
            // On macOS 26 Tahoe, button might not be immediately available
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.setupMainItemButtonWithRetry(image: image, attempt: attempt + 1)
                }
                print("⚠️ Status bar button not ready, retrying... (attempt \(attempt + 1))")
            } else {
                print("❌ Failed to setup status bar button after 5 attempts")
            }
            return
        }
        
        // Button is available, configure it
        mainItemButton.image = NSImage(named: image)
        mainItemButton.image?.size = NSSize(width: 18, height: 18)
        mainItemButton.image?.isTemplate = true
        mainItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
        mainItemButton.action = #selector(togglePopover(sender:))
        mainItemButton.target = self
        print("✅ Status bar button setup successfully")
    }
    
    private func setMainItemButton(image: String) {
        guard let mainItemButton = mainItem.button else {
            print("⚠️ Cannot update status bar button - button is nil")
            // Try to setup with retry if button became nil
            setupMainItemButtonWithRetry(image: image)
            return
        }
        
        mainItemButton.image = NSImage(named: image)
        mainItemButton.image?.size = NSSize(width: 18, height: 18)
        mainItemButton.image?.isTemplate = true
        mainItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
        mainItemButton.action = #selector(togglePopover(sender:))
        mainItemButton.target = self
    }

    private func setMarkButton(attempt: Int = 0) {
        if markItem == nil {
            markItem = NSStatusBar.system.statusItem(withLength: MarkItemLength.normal)
            if let markItem {
                Self.configureStatusItem(markItem)
            }
        }
        
        guard let markItemButton = markItem?.button else {
            // On macOS 26 Tahoe, button might not be immediately available
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.setMarkButton(attempt: attempt + 1)
                }
                print("⚠️ Mark button not ready, retrying... (attempt \(attempt + 1))")
            } else {
                print("❌ Failed to setup mark button after 5 attempts")
            }
            return
        }
        
        markItemButton.image = NSImage(named: "mark_icon")
        markItemButton.image?.size = NSSize(width: 22, height: 18)
        markItemButton.image?.isTemplate = true
        markItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
        markItemButton.action = #selector(showMenuBarIcons(sender:))
        markItemButton.target = self
        print("✅ Mark button setup successfully")
    }

    private func observeNotifications() {
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

    isolated deinit {
        if let systemMonitorPreferencesObserver {
            NotificationCenter.default.removeObserver(systemMonitorPreferencesObserver)
        }
        nativeVisibilityApplier?.invalidateSynchronously()
        HideMenubarIconsSwitch.shared.clearTransition(owner: menuBarTransitionOwner)
        if let markItem {
            NSStatusBar.system.removeStatusItem(markItem)
        }
    }

    @MainActor
    private func handleHidePopover() {
        if let statusBarButton = mainItem.button {
            hidePopover(statusBarButton)
        }
    }
    
    func showPopover(_ sender: AnyObject?) {
        // Ensure we're on the main thread for UI operations
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover(sender)
            }
            return
        }
        
        guard let statusBarButton = mainItem.button else {
            print("⚠️ Status bar button not available")
            return
        }
        
        if currentAppearance == .onlyControl {
            onlyControlWindow.show()
        } else {
            // macOS 26 Tahoe: Add safety check before showing popover
            guard !popover.isShown else {
                print("⚠️ Popover already shown")
                return
            }
            
            popover.show(relativeTo: statusBarButton.bounds,
                         of: statusBarButton,
                         preferredEdge: NSRectEdge.maxY)
            popover.contentViewController?.view.window?.makeKey()
        }

        NotificationCenter.default.post(name: .showPopover, object: nil)
        eventMonitor?.start()
    }

    @MainActor
    func hidePopover(_ sender: AnyObject?) {
        if #available(macOS 26.2, *) {
            let listAppearance = PreferencesObserver
                .shared
                .preferences
                .currentAppearance
            if let apperearance = SwitchListAppearance(rawValue: listAppearance) {
                let originalHeight = popover.contentSize.height
                popover.contentSize = NSSize(width: apperearance == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40, height: originalHeight)
            }
        }
        
        if currentAppearance == .onlyControl || onlyControlWindow.isShowing {
            popover.performClose(sender)
            onlyControlWindow.hide()
        } else {
            // macOS 26 Tahoe: Safety check before closing popover
            guard popover.isShown else {
                print("⚠️ Popover already hidden")
                return
            }
            popover.performClose(sender)
        }

        NotificationCenter.default.post(name: .hidePopover, object: nil)
        eventMonitor?.stop()
    }

    func mouseEventHandler(_ event: NSEvent?) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.mouseEventHandler(event)
            }
            return
        }

        let condition = currentAppearance == .onlyControl ? OnlyControlWindow.shared.isShowing : popover.isShown

        if condition {
            hidePopover(event)
        }
    }
}
