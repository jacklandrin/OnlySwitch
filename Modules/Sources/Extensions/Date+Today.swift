//
//  Date+Today.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/12.
//

import Foundation
public extension Date {
    func date(at hours: Int, minutes: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        
        var dateComponents = calendar.dateComponents([.year,.month,.day], from: self)
        
        dateComponents.hour = hours
        dateComponents.minute = minutes
        dateComponents.second = 0
        
        let newDate = calendar.date(from: dateComponents)!
        return newDate
    }
}
