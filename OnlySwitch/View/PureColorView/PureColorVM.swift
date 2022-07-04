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
            try? await ScreenTestSwitch.shared.operationSwitch(isOn: false)
        }
        
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.screenTest)
    }
    
}
