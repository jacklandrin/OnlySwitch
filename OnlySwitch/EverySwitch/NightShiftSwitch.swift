//
//  NightShiftSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/5.
//

import AppKit

class NightShiftSwitch:SwitchProvider {
    
    var type: SwitchType = .nightShift
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .nightShift)
    var barInfo: SwitchBarInfo = SwitchBarInfo(title: "Night Shift",
                                               onImage: NSImage(systemSymbolName: "moon.stars.fill"),
                                               offImage: NSImage(systemSymbolName: "moon.stars"))
    init() {
        switchBarVM.switchOperator = self
    }
    
    func isVisable() -> Bool {
        return NightShiftTool.supportsNightShift
    }
    
    static let shared = NightShiftSwitch()
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return NightShiftTool.isNightShiftEnabled
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            NightShiftTool.enable()
            NightShiftTool.strength = 1
        } else {
            NightShiftTool.strength = 0
            NightShiftTool.disable()
        }
        return true
    }
}

class NightShiftTool {
    private static let client = CBBlueLightClient()

    private static var blueLightStatus: Status {
        var status: Status = Status()
        client.getBlueLightStatus(&status)
        return status
    }

    static var strength: Float {
        get {
            var strength: Float = 0
            client.getStrength(&strength)
            return strength
        }
        set {
            client.setStrength(newValue, commit: true)
        }
    }

    static func previewStrength(_ value: Float) {
        // Check if user manually disabled Night Shift
        if !isNightShiftEnabled { isNightShiftEnabled = true }
        client.setStrength(value, commit: false)
    }

    static var isNightShiftEnabled: Bool {
        get { return blueLightStatus.enabled.boolValue }
        set { client.setEnabled(newValue) }
    }

    public static func enable() {
        isNightShiftEnabled = true
    }

    public static func disable() {
        isNightShiftEnabled = false
    }

    static var supportsNightShift: Bool { return CBBlueLightClient.supportsBlueLightReduction() }
}
