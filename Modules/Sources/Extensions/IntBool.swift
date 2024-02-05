//
//  IntBool.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/12.
//

import Foundation
public extension Bool {
    var intValue: Int {
        return self ? 1 : 0
    }
}

public extension Int {
    var boolValue: Bool {
        return self != 0
    }
}
