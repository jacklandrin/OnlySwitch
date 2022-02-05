//
//  StatusBarController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit

let showPopoverNotificationName = NSNotification.Name("showPopover")
let hidePopoverNotificationName = NSNotification.Name("hidePopover")
let shouldHidePopoverNotificationName = NSNotification.Name("shouldHidePopover")
let changeMenuBarIconNotificationName = NSNotification.Name("changeMenuBarIcon")
let changePopoverAppearanceNotificationName = NSNotification.Name("changePopoverAppearanceNotificationName")

struct OtherPopover {
    static let name = NSNotification.Name("otherPopover")
    static func hasShown(_ hasShown:Bool) {
        NotificationCenter.default.post(name: name, object: hasShown)
    }
}

class StatusBarController {

    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor : EventMonitor?
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
    @UserDefaultValue(key: menubarIconKey, defaultValue: "menubar_0")
    var currentMenubarIcon:String
    
    @UserDefaultValue(key: appearanceColumnCountKey, defaultValue: SwitchListAppearance.single.rawValue)
    var currentAppearance:String
    
    private var otherPopoverBitwise:Int = 0
    
    init(_ popover:NSPopover) {
        self.popover = popover
        
        
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        
        setStatusBarButton(image: currentMenubarIcon)
        
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)
        
        NotificationCenter.default.addObserver(forName: changeMenuBarIconNotificationName, object: nil, queue: .main, using: {[weak self] notify in
            guard let strongSelf = self else {return}
            let newImageName = notify.object as! String
            strongSelf.setStatusBarButton(image: newImageName)
        })
        
        NotificationCenter.default.addObserver(forName: shouldHidePopoverNotificationName, object: nil, queue: .main, using: {[weak self] notify in
            guard let strongSelf = self else {return}
            if let statusBarButton = strongSelf.statusItem.button {
                strongSelf.hidePopover(statusBarButton)
            }
            
        })
        
        NotificationCenter.default.addObserver(forName: OtherPopover.name, object: nil, queue: .main, using: { [weak self] notify in
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
        
        NotificationCenter.default.addObserver(forName: changePopoverAppearanceNotificationName, object: nil, queue: .main, using: { [weak self] notify in
            guard let strongSelf = self else {return}
            strongSelf.hidePopover(nil)
            let appearance = SwitchListAppearance(rawValue: strongSelf.currentAppearance)
            if appearance == .single {
                strongSelf.popover.contentSize.width = popoverWidth
            } else if appearance == .dual {
                strongSelf.popover.contentSize.width = popoverWidth * 2 - 50
            }
        })
    }
    
    @objc func togglePopover(sender:AnyObject) {
        if hasOtherPopover {
            return
        }
        if(popover.isShown) {
            hidePopover(sender)
        } else {
            showPopover(sender)
        }
    }
    
    func setStatusBarButton(image:String) {
        if let statusBarButton = statusItem.button {
            statusBarButton.image = NSImage(named: image)
            statusBarButton.image?.size = NSSize(width: 18, height: 18)
            statusBarButton.image?.isTemplate = true

            statusBarButton.action = #selector(togglePopover(sender:))
            statusBarButton.target = self
        }
    }
    
    func showPopover(_ sender: AnyObject) {
        if let statusBarButton = statusItem.button {
            popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: NSRectEdge.maxY)
            popover.contentViewController?.view.window?.makeKey()
            NotificationCenter.default.post(name: showPopoverNotificationName, object: nil)
            eventMonitor?.start()
        }
    }
        
    func hidePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        NotificationCenter.default.post(name: hidePopoverNotificationName, object: nil)
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
