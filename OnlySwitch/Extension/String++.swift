//
//  String++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

extension String {
    func runAppleScript(isShellCMD:Bool = false) -> (Bool, Any) {
        var finalCommand = self
        if isShellCMD {
            finalCommand = "do shell script \"\(self)\""
        }
        var error: NSDictionary?
        if let scroptObject = NSAppleScript(source: finalCommand) {
            let descriptor = scroptObject.executeAndReturnError(&error)
//            let outputArray = descriptor.toDicArray()
            if let outputString = descriptor.stringValue {
                print(outputString)
                return (true, outputString)
//            } else if outputArray.count > 0 {
//                return (true, outputArray)
            } else if error != nil {
                print("error:\(String(describing: error!))")
                return (false, "failed")
            }
        }
        return (true, "")
    }
}
