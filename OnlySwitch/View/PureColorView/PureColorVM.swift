//
//  PureColorVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/22.
//

import SwiftUI
import CoreGraphics

class PureColorVM:ObservableObject {
    
    private var runLoopSource:CFRunLoopSource?
    
    private var isLeftArrowPressed = false
    {
        didSet {
            if isLeftArrowPressed {
                if colorIndex > 0 {
                    colorIndex -= 1
                } else {
                    colorIndex = colorList.count - 1
                }
                withAnimation{
                    currentColor = colorList[colorIndex]
                }
            }
        }
    }
    
    private var isRightArrowPressed = false
    {
        didSet {
            if isRightArrowPressed {
                if colorIndex < colorList.count - 1 {
                    colorIndex += 1
                } else {
                    colorIndex = 0
                }
                withAnimation{
                    currentColor = colorList[colorIndex]
                }
            }
        }
    }
    
    private var colorList:[Color] = [.black, .white, .red, .green, .blue]
    private var colorIndex:Int = 0
    @Published var currentColor: Color = .black
    @Published var tipAlpha = 1.0
    
    
    var isHovering:Bool = false
    {
        didSet {
            tipAlpha = isHovering ? 1.0 : 0.0
        }
    }
    
    func pressLeftButton() {
        if colorIndex > 0 {
            colorIndex -= 1
        } else {
            colorIndex = colorList.count - 1
        }
        withAnimation{
            currentColor = colorList[colorIndex]
        }
    }
    
    func pressRightButton() {
        if colorIndex < colorList.count - 1 {
            colorIndex += 1
        } else {
            colorIndex = 0
        }
        withAnimation{
            currentColor = colorList[colorIndex]
        }
    }
    
    func exitScreenTestMode() {
        Task {
            try? await ScreenTestSwitch.shared.operateSwitch(isOn: false)
        }
    }
    
    
    func forbiddenKeyboard() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << 14) //power button
        
        let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: {(eventTapProxy, eventType, event, mutablePointer) -> Unmanaged<CGEvent>? in event
                return nil
            },
            userInfo: nil)

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, CFIndex(0))
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }
    
    func recoverKeyboard() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
    
}
