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
        try testSwitch(aSwitch: darkModeSwitch)
    }

    func testHiddenDesktopSwitch() throws {
        let hiddenDesktopSwitch = HiddenDesktopSwitch()
        try testSwitch(aSwitch: hiddenDesktopSwitch)
    }
    
    func testTopNotchSwitch() throws {
        let topNotchSwitch = TopNotchSwitch()
        try testSwitch(aSwitch: topNotchSwitch)
    }
    
    
    private func testSwitch(aSwitch:SwitchProvider) throws {
        let exp = expectation(description: "get status")
        Task {
            try await aSwitch.operationSwitch(isOn:true)
            DispatchQueue.main.async {
                let currentStatus = aSwitch.currentStatus()
                XCTAssertEqual(currentStatus, true)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5.0)
    }
}
