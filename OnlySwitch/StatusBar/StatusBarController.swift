//
//  StatusBarController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit
import Defines
import SwiftUI
import Foundation
import ComposableArchitecture

@MainActor
class StatusBarController {
    struct MarkItemLength {
        static let collapse:CGFloat = 10000
        static let normal:CGFloat = NSStatusItem.squareLength
    }

    private var mainItem: NSStatusItem
    private var markItem: NSStatusItem?
    /// Own menu bar item for the sound mixer, so it is one click away instead of buried in Settings.
    private var mixerItem: NSStatusItem?
    private var popover: NSPopover
    private var eventMonitor : EventMonitor?
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
        
        // macOS 26 Tahoe: Button might not be immediately available, retry if needed
        setupMainItemButtonWithRetry(image: currentMenubarIcon)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.mouseEventHandler(event)
        }

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

        // Before the mark item on purpose: status items are added left of the existing ones, and
        // collapsing hides everything left of the mark. Creating the mixer first keeps it on the
        // mark's right, where it stays reachable while the menu bar is collapsed.
        if Preferences.shared.soundMixerMenubarItem {
            setMixerButton()
        }

        if menubarCollaspable {
            setMarkButton()
            Task {
                try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: isMenubarCollapse)
            }
        }

        observeNotifications()
    }

    // MARK: - Sound mixer item

    private lazy var mixerPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: SoundMixerPopoverView())
        // Let the panel drive the popover height — the app list grows and shrinks with what plays.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        return popover
    }()

    private func setMixerButton() {
        guard mixerItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                                     accessibilityDescription: "Sound".localized())
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(toggleMixerPopover(sender:))
        mixerItem = item
    }

    /// Adds or removes the mixer item at runtime.
    ///
    /// A freshly created item lands leftmost, which would put it *left* of the mark item and let
    /// "hide menu bar icons" swallow it. So the mark item is rebuilt afterwards to reclaim the
    /// leftmost spot, and expanded — a collapsed rebuild would hide the icon the user just enabled.
    private func setMixerItemEnabled(_ enable: Bool) {
        guard enable else {
            if let mixerItem {
                if mixerPopover.isShown { mixerPopover.performClose(nil) }
                NSStatusBar.system.removeStatusItem(mixerItem)
                self.mixerItem = nil
            }
            return
        }

        setMixerButton()

        guard let markItem else { return }
        NSStatusBar.system.removeStatusItem(markItem)
        self.markItem = nil
        setMarkButton()
        Task {
            try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
        }
    }

    @objc private func toggleMixerPopover(sender: AnyObject?) {
        guard let button = mixerItem?.button else { return }
        if mixerPopover.isShown {
            mixerPopover.performClose(sender)
        } else {
            mixerPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Without this the popover opens behind the frontmost app and swallows the first click.
            mixerPopover.contentViewController?.view.window?.makeKey()
        }
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
                if markItem?.length == MarkItemLength.collapse {
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
            if markItem?.length == MarkItemLength.normal {
                try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: true)
            }
        }
    }

    private var isMarkItemValidPosition:Bool {
        guard let mainItemX = self.mainItem.button?.getOrigin?.x,
              let markItemX = self.markItem?.button?.getOrigin?.x
        else {return false}
        return mainItemX >= markItemX
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
            forName: .toggleMenubarCollapse,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            let isOn = notify.object as? Bool
            Task { @MainActor [weak self] in
                guard let self, let isOn else { return }
                self.markItem?.length = isOn ? MarkItemLength.collapse : MarkItemLength.normal
            }
        }

        NotificationCenter.default.addObserver(
            forName: .toggleSoundMixerItem,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            let enable = notify.object as? Bool
            Task { @MainActor [weak self] in
                guard let self, let enable else { return }
                self.setMixerItemEnabled(enable)
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
                    Task {
                        try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                    }
                } else if let markItem = self.markItem {
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
