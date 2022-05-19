//
//  EverySwitchTests.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import XCTest

class EverySwitchTests: XCTestCase {
    func testDarkModeSwitch() throws {
        let darkModeSwitch = DarkModeSwitch()
        Task {
            try await darkModeSwitch.operationSwitch(isOn: true)
            DispatchQueue.main.async {
                let currentStatus = darkModeSwitch.currentStatus()
                XCTAssertEqual(currentStatus, true)
            }
        }
    }

    func testHiddenDesktopSwitch() throws {
        let hiddenDesktopSwitch = HiddenDesktopSwitch()
        Task {
            try await hiddenDesktopSwitch.operationSwitch(isOn:true)
            DispatchQueue.main.async {
                let currentStatus = hiddenDesktopSwitch.currentStatus()
                XCTAssertEqual(currentStatus, true)
            }
        }
    }
    
}
