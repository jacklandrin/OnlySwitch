//
//  EventMonitor.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Cocoa

class EventMonitor {
    private var monitor:Any?
    private var mask : NSEvent.EventTypeMask
    private let handler:(NSEvent?) -> Void
    
    init(mask:NSEvent.EventTypeMask, handler:@escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask,handler:handler) as! NSObject
    }
    
    func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
}
