//
//  StatusBarController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import AppKit

let showPopoverNotificationName = NSNotification.Name("showPopover")
let hidePopoverNotificationName = NSNotification.Name("hidePopover")

struct OtherPopover {
    static let name = NSNotification.Name("otherPopover")
    static func hasShown(_ hasShown:Bool) {
        NotificationCenter.default.post(name: name, object: hasShown)
    }
}

class StatusBarController {
//    private var statusBar: NSStatusBar
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
    private var otherPopoverBitwise:Int = 0
    init(_ popover:NSPopover) {
        self.popover = popover
//        statusBar = NSStatusBar()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)//statusBar.statusItem(withLength: 28)
        if let statusBarButton = statusItem.button {
            statusBarButton.image = #imageLiteral(resourceName: "statusbar")
            statusBarButton.image?.size = NSSize(width: 18, height: 18)
            statusBarButton.image?.isTemplate = true
            
            statusBarButton.action = #selector(togglePopover(sender:))
            statusBarButton.target = self
        }
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)
        
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
    }
    
    @objc func togglePopover(sender:AnyObject) {
        if hasOtherPopover {
            return
        }
        if(popover.isShown) {
            hidePopover(sender)
        }
        else {
            showPopover(sender)
        }
    }
    
    func showPopover(_ sender: AnyObject) {
        if let statusBarButton = statusItem.button {
            popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: NSRectEdge.maxY)
            NotificationCenter.default.post(name: showPopoverNotificationName, object: nil)
            eventMonitor?.start()
        }
    }
        
    func hidePopover(_ sender: AnyObject) {
        popover.performClose(sender)
        NotificationCenter.default.post(name: hidePopoverNotificationName, object: nil)
        eventMonitor?.stop()
    }

    func mouseEventHandler(_ event:NSEvent?) {
        if hasOtherPopover {
            return
        }
        if popover.isShown {
            hidePopover(event!)
        }
    }
    
}
