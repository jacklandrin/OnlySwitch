//
//  EverySwitchTests.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import XCTest
@testable import IOBluetooth
@testable import CoreBluetooth

class EverySwitchTests: XCTestCase {
    func testDarkModeSwitch() throws {
        let darkModeSwitch = DarkModeSwitch()
        try testSwitch(aSwitch: darkModeSwitch, isOn: true)
    }

    func testHiddenDesktopSwitch() throws {
        let hiddenDesktopSwitch = HiddenDesktopSwitch()
        try testSwitch(aSwitch: hiddenDesktopSwitch, isOn: true)
    }
    
    func testTopNotchSwitch() throws {
        let topNotchSwitch = TopNotchSwitch()
        try testSwitch(aSwitch: topNotchSwitch, isOn: true)
    }
    
    func testMuteSwitch() throws {
        let muteSwitch = MuteSwitch()
        try testSwitch(aSwitch: muteSwitch, isOn: true)
    }
    
    func testScreenSaverSwitch() throws {
        let screenSaverSwitch = ScreenSaverSwitch()
        try testSwitch(aSwitch: screenSaverSwitch, isOn: true)
    }
    
    func testNightShiftSwitch() throws {
        let nightShiftSwitch = NightShiftSwitch()
        try testSwitch(aSwitch: nightShiftSwitch, isOn: true)
    }
    
    func testAutohideDockSwitch() throws {
        let autohideDockSwitch = AutohideDockSwitch()
        try testSwitch(aSwitch: autohideDockSwitch, isOn: true)
    }
    
    func testAirPodsSwitch() throws {
        let _ = BluetoothDevicesManager.shared
        let exp = expectation(description: "wait bluetooth callback")
        wait(for: [exp], timeout: 10)
        let airPodsSwitch = AirPodsSwitch()
        if airPodsSwitch.isVisable() {
            let status = airPodsSwitch.currentStatus()
            try testSwitch(aSwitch: airPodsSwitch, isOn: !status)
        }
        
    }
    
    func testAutohideMenuBarSwitch() throws {
        let autohideMenuBarSwitch = AutohideMenuBarSwitch()
        try testSwitch(aSwitch: autohideMenuBarSwitch, isOn: false)
    }
    
    func testHiddenFilesSwitch() throws {
        let hiddenFilesSwitch = HiddenDesktopSwitch()
        try testSwitch(aSwitch: hiddenFilesSwitch, isOn: true)
    }
    
    func testKeepAwakeSwitch() throws {
        let keepAwakeSwitch = KeepAwakeSwitch()
        try testSwitch(aSwitch: keepAwakeSwitch, isOn: true)
    }
    
//    func testEmptyTrashSwitch() throws {
//        let emptyTrashSwitch = EmptyTrashSwitch()
//        try testSwitch(aSwitch: emptyTrashSwitch, isOn: true)
//    }
    
    func testShowUserLibrarySwitch() throws {
        let showUserLibrarySwitch = ShowUserLibrarySwitch()
        try testSwitch(aSwitch: showUserLibrarySwitch, isOn: true)
    }
    
    func testShowExtensionNameSwitch() throws {
        let showExtensionNameSwitch = ShowExtensionNameSwitch()
        try testSwitch(aSwitch: showExtensionNameSwitch, isOn: true)
    }
    
    func testSmallLaunchpadIconSwitch() throws {
        let smallLaunchpadIconSwitch = SmallLaunchpadIconSwitch()
        try testSwitch(aSwitch: smallLaunchpadIconSwitch, isOn: true)
    }
    
    func testLowPowerModeSwitch() throws {
        let lowPowerModeSwitch = LowPowerModeSwitch()
        try testSwitch(aSwitch: lowPowerModeSwitch, isOn: false)
    }
    
    func testMuteMicSwitch() throws {
        let muteMicSwitch = MuteMicSwitch()
        try testSwitch(aSwitch: muteMicSwitch, isOn: false)
    }
    
    func testShowFinderPathbarSwitch() throws {
        let showFinderPathbarSwitch = ShowFinderPathbarSwitch()
        try testSwitch(aSwitch: showFinderPathbarSwitch, isOn: true)
    }
    
    func testDockRecentSwitch() throws {
        let dockRecentSwitch = DockRecentSwitch()
        try testSwitch(aSwitch: dockRecentSwitch, isOn: true)
    }
    
    private func testSwitch(aSwitch:SwitchProvider, isOn:Bool) throws {
        let exp = expectation(description: "get status")
        Task {
            try await aSwitch.operationSwitch(isOn:isOn)
            DispatchQueue.main.async {
                let currentStatus = aSwitch.currentStatus()
                XCTAssertEqual(currentStatus, isOn)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 15.0)
    }
}
