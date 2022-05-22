//
//  PureColorVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/22.
//

import SwiftUI
class PureColorVM:ObservableObject {
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
    
    fileprivate var keyStates: [CGKeyCode: Bool] =
    [
        .kVK_LeftArrow: false,
        .kVK_RightArrow: false
        // populate with other key codes you're interested in
    ]

    
    private let pollingInterval: DispatchTimeInterval = .milliseconds(50)
    private let pollingQueue = DispatchQueue.main
    
    private func dispatchKeyDown(_ key:CGKeyCode) {
        DispatchQueue.main.async {
            if key == .kVK_LeftArrow {
                self.isLeftArrowPressed = true
            } else if key == .kVK_RightArrow {
                self.isRightArrowPressed = true
            }
            print("key down")
        }
    }
    
   private func dispatchKeyUp(_ key:CGKeyCode) {
        DispatchQueue.main.async {
            if key == .kVK_LeftArrow {
                self.isLeftArrowPressed = false
            } else if key == .kVK_RightArrow {
                self.isRightArrowPressed = false
            }
            print("key up")
        }
    }
    
    private func pollKeyStates() {
        for (code, wasPressed) in keyStates {
            if code.isPressed {
                if !wasPressed {
                    dispatchKeyDown(code)
                    keyStates[code] = true
                }
            } else if wasPressed {
                dispatchKeyUp(code)
                keyStates[code] = false
            }
        }
        if Router.isShown(windowController: Router.pureColorWindowController) {
            scheduleNextPoll(on: pollingQueue)
        }
    }
    
    
    private func scheduleNextPoll(on queue: DispatchQueue) {
       queue.asyncAfter(deadline: .now() + pollingInterval) {
           self.pollKeyStates()
       }
    }

    func startDetectKeyboard() {
        scheduleNextPoll(on: pollingQueue)
    }

}
