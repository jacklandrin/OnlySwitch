//
//  CustomizeVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import AppKit
import Foundation
import KeyboardShortcuts
import Switches
import Utilities

@MainActor
class CustomizeVM:ObservableObject {
    static let shared  = CustomizeVM()
    @Published var allSwitches:[CustomizeItem] = [CustomizeItem]()
    @Published var errorInfo = ""
    @Published var showErrorToast = false
    init() {
        let visibleTypes = SwitchManager.shared.visibleSwitchTypes()
        for type in SwitchType.allCases {
            let isVisible = visibleTypes.contains(type)
            allSwitches.append(CustomizeItem(type: type, toggle: isVisible, error: { [weak self] info in
                guard let strongSelf = self else {return}
                strongSelf.errorInfo = info
                strongSelf.showErrorToast = true
            }))
        }
    }
}

@MainActor
class CustomizeItem: ObservableObject {
    let type:SwitchType
    let barInfo: SwitchBarInfo
    let iconImage: NSImage?
    let error:(_ info:String) -> Void
    @Published var toggle:Bool
    {
        didSet {
            if toggle {
                SwitchManager.shared.setVisible(true, for: type)
            } else {
                if SwitchManager.shared.shownSwitchCount < 5 {
                    error("At least remain 4 switches")
                    toggle = true
                    return
                }
                SwitchManager.shared.setVisible(false, for: type)
            }
        }
    }
    
    @Published var keyboardShortcutName:KeyboardShortcuts.Name
    
    init(type:SwitchType, toggle:Bool, error:@escaping (_ info:String) -> Void) {
        self.type = type
        self.barInfo = type.barInfo()
        self.iconImage = barInfo.onImage?.resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))
        self.toggle = toggle
        self.error = error
        self.keyboardShortcutName = KeyboardShortcuts.Name(rawValue: String(type.legacyIdentifier))!
    }

    @MainActor
    func doSwitch() async {
        type.doSwitch()
    }
}
