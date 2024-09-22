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

struct OtherPopover {
    static let name = NSNotification.Name("otherPopover")
    static func hasShown(_ hasShown:Bool) {
        NotificationCenter.default.post(name: name, object: hasShown)
    }
}

class StatusBarController {

    struct MarkItemLength {
        static let collapse:CGFloat = 10000
        static let normal:CGFloat = NSStatusItem.squareLength
    }

    private var mainItem: NSStatusItem
    private var markItem: NSStatusItem?
    private var popover: NSPopover
    private var onlyControlStore: StoreOf<OnlyControlReducer> = .init(initialState: .init()) { OnlyControlReducer() }
    private var eventMonitor : EventMonitor?
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    private var isMenubarCollapse:Bool
    private var hasOtherPopover = false
    {
        didSet {
            if hasOtherPopover {
                eventMonitor?.stop()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.eventMonitor?.start()
                }
            }
        }
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

    lazy var dashboardWindow: NSWindow = {
        let view = NSHostingView(rootView: OnlyControlView(store: onlyControlStore))
        let window = OnlyControlWindow(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: .main
        )
        let contentRect = window.contentRect(forFrameRect: window.frame)
        view.frame = contentRect
        window.contentView = view

        [window].forEach {
            $0.isMovable = true
            $0.collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
            $0.level = .mainMenu
            $0.ignoresMouseEvents = false
            $0.hasShadow = true
            $0.isReleasedWhenClosed = false
            $0.backgroundColor = .clear
            $0.isMovableByWindowBackground = true
            $0.isOpaque = false
        }

        window.makeKeyAndOrderFront(nil)
        window.center()
        window.setFrameUsingName("OnlyControlWindow")
        window.setFrameAutosaveName("OnlyControlWindow")
        return window
    }()

    private var otherPopoverBitwise:Int = 0

    init(_ popover: NSPopover) {
        self.popover = popover

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setMainItemButton(image: currentMenubarIcon)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)

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
            Task {
                try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: isMenubarCollapse)
            }
        }

        observeNotifications()
    }

    @objc private func togglePopover(sender:AnyObject?) {
        if let event = NSApp.currentEvent, event.isRightClicked {
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

            let condition = currentAppearance == .onlyControl ? dashboardWindow.isVisible : popover.isShown

            if(condition) {
                hidePopover(sender)
            } else {
                showPopover(sender)
            }
        }
    }

    @objc private func showMenuBarIcons(sender:AnyObject) {
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

    private func setMainItemButton(image:String) {
        if let mainItemButton = mainItem.button {
            mainItemButton.image = NSImage(named: image)
            mainItemButton.image?.size = NSSize(width: 18, height: 18)
            mainItemButton.image?.isTemplate = true
            mainItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
            mainItemButton.action = #selector(togglePopover(sender:))
            mainItemButton.target = self
        }
    }

    private func setMarkButton() {
        markItem = NSStatusBar.system.statusItem(withLength: MarkItemLength.normal)
        if let markItemButton = markItem?.button {
            markItemButton.image = NSImage(named: "mark_icon")
            markItemButton.image?.size = NSSize(width: 22, height: 18)
            markItemButton.image?.isTemplate = true
            markItemButton.sendAction(on: [.leftMouseDown, .rightMouseDown])
            markItemButton.action = #selector(showMenuBarIcons(sender:))
            markItemButton.target = self
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(forName: .changeMenuBarIcon,
                                               object: nil,
                                               queue: .main,
                                               using: {[weak self] notify in
            guard let self else {return}
            let newImageName = notify.object as! String
            self.setMainItemButton(image: newImageName)
        })

        NotificationCenter.default.addObserver(forName: .togglePopover,
                                               object: nil,
                                               queue: .main,
                                               using: { [weak self] notify in
            guard let self else {return}
            self.togglePopover(sender: nil)
        })

        NotificationCenter.default.addObserver(
            forName: .shouldHidePopover,
            object: nil,
            queue: .main,
            using: { [weak self] notify in
                guard let self else {return}
                if let statusBarButton = self.mainItem.button {
                    self.hidePopover(statusBarButton)
                }

            }
        )

        NotificationCenter.default.addObserver(
            forName: OtherPopover.name,
            object: nil,
            queue: .main,
            using: { [weak self] notify in
                guard let self else {return}
                let hasShown = notify.object as! Bool
                if hasShown {
                    self.otherPopoverBitwise = self.otherPopoverBitwise << 1 + 1
                } else {
                    self.otherPopoverBitwise = self.otherPopoverBitwise >> 1
                }
                var existOtherPopover = false
                if self.otherPopoverBitwise == 0 {
                    existOtherPopover = false
                } else {
                    existOtherPopover = true
                }

                if existOtherPopover != self.hasOtherPopover {
                    self.hasOtherPopover = existOtherPopover
                }
            }
        )

        NotificationCenter.default.addObserver(
            forName: .changePopoverAppearance,
            object: nil,
            queue: .main,
            using: { [weak self] notify in
                guard let self else {return}
                self.hidePopover(nil)

                if self.currentAppearance == .single {
                    self.popover.contentSize.width = Layout.popoverWidth
                } else if self.currentAppearance == .dual {
                    self.popover.contentSize.width = Layout.popoverWidth * 2 - 40
                }
            }
        )

        NotificationCenter.default.addObserver(
            forName: .toggleMenubarCollapse,
            object: nil,
            queue: .main,
            using: { [weak self] notify in
                guard let self, let isOn = notify.object as? Bool else {return}
                self.markItem?.length = isOn ? MarkItemLength.collapse : MarkItemLength.normal
            }
        )

        NotificationCenter.default.addObserver(
            forName: .menubarCollapsable,
            object: nil,
            queue: .main,
            using: {[weak self] notify in
                guard let self, let enable = notify.object as? Bool else {return}
                if enable {
                    self.setMarkButton()
                    Task {
                        try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                    }

                } else {
                    if let markItem = self.markItem {
                        NSStatusBar.system.removeStatusItem(markItem)
                    }
                }
            }
        )
    }

    func showPopover(_ sender: AnyObject?) {
        if let statusBarButton = mainItem.button {
            if currentAppearance == .onlyControl {
                dashboardWindow.makeKeyAndOrderFront(nil)
                onlyControlStore.send(.showControl)
            } else {
                popover.show(relativeTo: statusBarButton.bounds,
                             of: statusBarButton,
                             preferredEdge: NSRectEdge.maxY)
                popover.contentViewController?.view.window?.makeKey()
            }

            NotificationCenter.default.post(name: .showPopover, object: nil)
            eventMonitor?.start()
        }
    }

    func hidePopover(_ sender: AnyObject?) {
        if currentAppearance == .onlyControl {
            onlyControlStore.send(.hideControl)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.51) {
                self.dashboardWindow.close()
            }
        } else {
            popover.performClose(sender)
        }

        NotificationCenter.default.post(name: .hidePopover, object: nil)
        eventMonitor?.stop()
    }

    func mouseEventHandler(_ event: NSEvent?) {
        if hasOtherPopover {
            return
        }

        let condition = currentAppearance == .onlyControl ? dashboardWindow.isVisible : popover.isShown

        if condition {
            hidePopover(event)
        }
    }
}
