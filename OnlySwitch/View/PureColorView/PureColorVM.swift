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

    fileprivate let sleepSem = DispatchSemaphore(value: 0)
    fileprivate let keyboardDetectConcurrentQueue = DispatchQueue(label: "polling", attributes: .concurrent)
    
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
    
    func startDetectKeyboard() {
        var condition = true
        keyboardDetectConcurrentQueue.async
        {
            while condition
            {
                for (code, wasPressed) in self.keyStates
                {
                    if code.isPressed
                    {
                        if !wasPressed
                        {
                            self.dispatchKeyDown(code)
                            self.keyStates[code] = true
                        }
                    }
                    else if wasPressed
                    {
                        self.dispatchKeyUp(code)
                        self.keyStates[code] = false
                    }
                }
                
                // Sleep long enough to avoid wasting CPU cycles, but
                // not so long that you miss key presses.  You may
                // need to experiment with the .milliseconds value.
                let _ = self.sleepSem.wait(timeout: .now() + .milliseconds(50))
                DispatchQueue.main.async {
                    condition = Router.isShown(windowController: Router.pureColorWindowController)
                }
            }
        }
    }

}
