//
//  SwitchProtocal.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

protocol SwitchProtocal {
    func currentStatus() -> Bool
    func operationSwitch(isOn:Bool) -> Bool
}
