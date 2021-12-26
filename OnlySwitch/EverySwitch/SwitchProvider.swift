//
//  SwitchProtocal.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation
import Combine

protocol SwitchProvider:AnyObject {
    var type:SwitchType {get set}
    var switchBarVM:SwitchBarVM {get set}
    func currentStatus() -> Bool
    func currentInfo() -> String
    func operationSwitch(isOn:Bool) async -> Bool
    func isVisable() -> Bool
}

extension SwitchProvider {
    func currentStatusAsync() async -> Bool {
        return currentStatus()
    }
    
    func currentInfoAsync() async -> String {
        return currentInfo()
    }
}
