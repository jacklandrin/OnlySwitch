//
//  StatusBarController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit


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
    
    var currentMenubarIcon:String {
        return Preferences.shared.currentMenubarIcon
    }
    
    var currentAppearance:String {
        return Preferences.shared.currentAppearance
    }
    
    private var otherPopoverBitwise:Int = 0
    
    init(_ popover:NSPopover) {
        self.popover = popover
        
        self.popover.behavior = .semitransient
        self.popover.animates = false
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
        
        if Preferences.shared.menubarCollaspable {
            setMarkButton()
            Task {
                try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: isMenubarCollapse)
            }
        }
        
        observeNotifications()
    }
    
    @objc private func togglePopover(sender:AnyObject) {
        if let event = NSApp.currentEvent, event.isRightClicked {
            guard Preferences.shared.menubarCollaspable else {return}
            Task {
                if markItem?.length == MarkItemLength.collapse {
                    try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                }
            }
        } else {
            if hasOtherPopover {
                return
            }
            if(popover.isShown) {
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
            guard let strongSelf = self else {return}
            let newImageName = notify.object as! String
            strongSelf.setMainItemButton(image: newImageName)
        })
        
        NotificationCenter.default.addObserver(forName: .shouldHidePopover,
                                               object: nil,
                                               queue: .main,
                                               using: {[weak self] notify in
            guard let strongSelf = self else {return}
            if let statusBarButton = strongSelf.mainItem.button {
                strongSelf.hidePopover(statusBarButton)
            }
            
        })
        
        NotificationCenter.default.addObserver(forName: OtherPopover.name,
                                               object: nil,
                                               queue: .main,
                                               using: { [weak self] notify in
            guard let strongSelf = self else {return}
            let hasShown = notify.object as! Bool
            if hasShown {
                strongSelf.otherPopoverBitwise = strongSelf.otherPopoverBitwise << 1 + 1
            } else {
                strongSelf.otherPopoverBitwise = strongSelf.otherPopoverBitwise >> 1
            }
            var existOtherPopover = false
            if strongSelf.otherPopoverBitwise == 0 {
                existOtherPopover = false
            } else {
                existOtherPopover = true
            }
            
            if existOtherPopover != strongSelf.hasOtherPopover {
                strongSelf.hasOtherPopover = existOtherPopover
            }
        })
        
        NotificationCenter.default.addObserver(forName: .changePopoverAppearance,
                                               object: nil,
                                               queue: .main,
                                               using: { [weak self] notify in
            guard let strongSelf = self else {return}
            strongSelf.hidePopover(nil)
            let appearance = SwitchListAppearance(rawValue: strongSelf.currentAppearance)
            if appearance == .single {
                strongSelf.popover.contentSize.width = Layout.popoverWidth
            } else if appearance == .dual {
                strongSelf.popover.contentSize.width = Layout.popoverWidth * 2 - 40
            }
        })
        
        NotificationCenter.default.addObserver(forName: .toggleMenubarCollapse,
                                               object: nil,
                                               queue: .main,
                                               using: { [weak self] notify in
            guard let strongSelf = self, let isOn = notify.object as? Bool else {return}
            strongSelf.markItem?.length = isOn ? MarkItemLength.collapse : MarkItemLength.normal
        })
        
        NotificationCenter.default.addObserver(forName: .menubarCollapsable,
                                               object: nil,
                                               queue: .main,
                                               using: {[weak self] notify in
            guard let strongSelf = self, let enable = notify.object as? Bool else {return}
            if enable {
                strongSelf.setMarkButton()
                Task {
                    try? await HideMenubarIconsSwitch.shared.operateSwitch(isOn: false)
                }
                
            } else {
                if let markItem = strongSelf.markItem {
                    NSStatusBar.system.removeStatusItem(markItem)
                }
            }
        })
    }
    
    func showPopover(_ sender: AnyObject) {
        if let statusBarButton = mainItem.button {
            popover.show(relativeTo: statusBarButton.bounds,
                         of: statusBarButton,
                         preferredEdge: NSRectEdge.maxY)
            popover.contentViewController?.view.window?.makeKey()
            NotificationCenter.default.post(name: .showPopover, object: nil)
            eventMonitor?.start()
        }
    }
        
    func hidePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        NotificationCenter.default.post(name: .hidePopover, object: nil)
        eventMonitor?.stop()
    }

    func mouseEventHandler(_ event:NSEvent?) {
        if hasOtherPopover {
            return
        }
        if popover.isShown {
            hidePopover(event)
        }
    }
    
}
