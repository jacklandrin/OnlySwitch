//
//  Float++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import Foundation
extension Float {
    /// Rounds the float to decimal places value
    func roundTo(places:Int) -> Float {
        let divisor = pow(10.0, Float(places))

        return (self * divisor).rounded() / divisor
    }
}
