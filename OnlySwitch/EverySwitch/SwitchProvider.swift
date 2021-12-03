//
//  SwitchProtocal.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

protocol SwitchProvider {
    func currentStatus() -> Bool
    func currentInfo() -> String
    func operationSwitch(isOn:Bool) async -> Bool
    func isVisable() -> Bool
}
