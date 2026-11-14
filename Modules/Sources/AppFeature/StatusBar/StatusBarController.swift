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
import Screenshots
import OSLog
import Extensions

enum ScreenshotShortcutAction: Equatable {
    case none
    case hide
    case reveal

    static func resolve(tabVisible: Bool, hostShown: Bool, selectedSection: SectionBar.Section) -> Self {
        guard tabVisible else { return .none }
        return hostShown && selectedSection == .screenshots ? .hide : .reveal
    }
}

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

    var mainItem: NSStatusItem
    var markItem: NSStatusItem?
    private var popover: NSPopover
    private var eventMonitor : EventMonitor?
    let menuBarTransitionOwner = UUID()
    let privateMenuBarBridge = MenuBarClientCoreBridgeAdapter()
    var nativeVisibilityApplier: MenuBarClientCoreVisibilityApplier!
    var menuBarIconHidingCoordinator: MenuBarIconHidingCoordinator!
    var systemMonitorStatusItems: SystemMonitorStatusItemController!
    var systemMonitorPreferencesObserver: NSObjectProtocol?
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    var isMenubarCollapse:Bool
    private var hasOtherPopover = false
    private let appearance: @MainActor () -> SwitchListAppearance
    private let configuresSystemIntegrations: Bool
    var listPreventsOutsideClickDismissal = false
    var listSelectedSection: SectionBar.Section = .controls

    private var onlyControlWindow: OnlyControlWindow {
        OnlyControlWindow.shared
    }

    var currentMenubarIcon: String {
        Preferences.shared.currentMenubarIcon
    }

    var currentAppearance: SwitchListAppearance {
        appearance()
    }

    var menubarCollaspable: Bool {
        Preferences.shared.menubarCollaspable
    }

    init(_ popover: NSPopover,
         appearance: @escaping @MainActor () -> SwitchListAppearance = { SwitchListAppearance(rawValue: Preferences.shared.currentAppearance) ?? .single },
         configuresSystemIntegrations: Bool = true) {
        self.popover = popover
        self.appearance = appearance
        self.configuresSystemIntegrations = configuresSystemIntegrations

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        Self.configureStatusItem(mainItem)
        guard configuresSystemIntegrations else { return }

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

    @objc func togglePopover(sender:AnyObject?) {
        // Safety check: ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover(sender: sender)
            }
            return
        }
        
        // macOS 26 Tahoe: Validate button still exists before proceeding
        guard mainItem.button != nil else {
            Logger.statusBar.warning("togglePopover called but status bar button is nil")
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
            Logger.statusBar.warning("showMenuBarIcons called but mark button is nil")
            return
        }
        
        guard let event = NSApp.currentEvent,
              let collapse = Self.markerClickTarget(isRightClick: event.isRightClicked, isCollapsed: isMenubarCollapse)
        else { return }
        Task {
            try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: collapse)
        }
    }

    /// Setup main item button with retry mechanism for macOS 26 compatibility
    private func setupMainItemButtonWithRetry(image: String, attempt: Int = 0) {
        guard let mainItemButton = mainItem.button else {
            // On macOS 26 Tahoe, button might not be immediately available
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.setupMainItemButtonWithRetry(image: image, attempt: attempt + 1)
                }
                Logger.statusBar.warning("Status bar button not ready, retrying... (attempt \(attempt + 1))")
            } else {
                Logger.statusBar.error("Failed to setup status bar button after 5 attempts")
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
        Logger.statusBar.info("Status bar button setup successfully")
    }
    
    func setMainItemButton(image: String) {
        guard let mainItemButton = mainItem.button else {
            Logger.statusBar.warning("Cannot update status bar button - button is nil")
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

    func setMarkButton(attempt: Int = 0) {
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
                Logger.statusBar.warning("Mark button not ready, retrying... (attempt \(attempt + 1))")
            } else {
                Logger.statusBar.error("Failed to setup mark button after 5 attempts")
            }
            return
        }
        
        markItemButton.image = NSImage(named: "mark_icon")
        markItemButton.image?.size = NSSize(width: 22, height: 18)
        markItemButton.image?.isTemplate = true
        markItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
        markItemButton.action = #selector(showMenuBarIcons(sender:))
        markItemButton.target = self
        Logger.statusBar.info("Mark button setup successfully")
    }

    isolated deinit {
        if let systemMonitorPreferencesObserver {
            NotificationCenter.default.removeObserver(systemMonitorPreferencesObserver)
        }
        nativeVisibilityApplier?.invalidateSynchronously()
        if configuresSystemIntegrations {
            HideMenubarIconsSwitch.shared.clearTransition(owner: menuBarTransitionOwner)
        } else {
            NSStatusBar.system.removeStatusItem(mainItem)
        }
        if let markItem {
            NSStatusBar.system.removeStatusItem(markItem)
        }
    }

    /// The keyboard shortcut closes only an already-visible Screenshots section. Captures continue to use
    /// the reveal-only client, so taking another screenshot never closes the host.
    func toggleScreenshotsSection(defaults: UserDefaults = .standard, presentation: ScreenshotPresentationClient = .app) {
        let tabVisible = defaults.object(forKey: UserDefaults.Key.showScreenshotsTab) as? Bool ?? true
        guard tabVisible else { return }
        let isOnlyControl = currentAppearance == .onlyControl
        let action = ScreenshotShortcutAction.resolve(
            tabVisible: tabVisible,
            hostShown: isOnlyControl ? onlyControlWindow.isShowing : popover.isShown,
            selectedSection: isOnlyControl ? onlyControlWindow.selectedSection : listSelectedSection
        )
        switch action {
        case .none:
            break
        case .hide:
            hidePopover(nil)
        case .reveal:
            _ = presentation.revealScreenshotsSection()
        }
    }

    /// A new screenshot asks for the list: show the current host if it is hidden. The host consumes its
    /// pending section request when it appears, even if it did not exist when the notification was posted.
    func revealScreenshotsHost() {
        guard !hasOtherPopover else { return }
        let isShowing = currentAppearance == .onlyControl ? onlyControlWindow.isShowing : popover.isShown
        guard !isShowing else { return }
        showPopover(nil)
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
            Logger.statusBar.warning("Status bar button not available")
            return
        }
        
        if currentAppearance == .onlyControl {
            onlyControlWindow.show()
        } else {
            // macOS 26 Tahoe: Add safety check before showing popover
            guard !popover.isShown else {
                Logger.statusBar.debug("Popover already shown")
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
        if #available(macOS 26.2, *), configuresSystemIntegrations {
            let listAppearance = PreferencesObserver
                .shared
                .preferences
                .currentAppearance
            if let apperearance = SwitchListAppearance(rawValue: listAppearance) {
                let originalHeight = popover.contentSize.height
                popover.contentSize = NSSize(width: apperearance == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40, height: originalHeight)
            }
        }
        
        if currentAppearance == .onlyControl || (configuresSystemIntegrations && onlyControlWindow.isShowing) {
            popover.performClose(sender)
            onlyControlWindow.hide()
        } else {
            // macOS 26 Tahoe: Safety check before closing popover
            guard popover.isShown else {
                Logger.statusBar.debug("Popover already hidden")
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

        if currentAppearance == .onlyControl {
            guard onlyControlWindow.isShowing, !onlyControlWindow.preventsOutsideClickDismissal else { return }
        } else {
            guard popover.isShown, !listPreventsOutsideClickDismissal else { return }
        }
        hidePopover(event)
    }
}
