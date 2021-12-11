//
//  SwitchProtocal.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation
import Combine

@objc protocol SwitchProvider {
    func currentStatus() -> Bool
    func currentInfo() -> String
    @objc optional func currentStatusAsync() async -> Bool
    @objc optional func currentInfoAsync() async -> String
    func operationSwitch(isOn:Bool) async -> Bool
    func isVisable() -> Bool
}

