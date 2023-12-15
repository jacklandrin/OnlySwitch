//
//  SwitchListTest.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import XCTest
@testable import OnlySwitch

class SwitchListTest:XCTestCase {
    var vm:SwitchListVM!
    override func setUp() {
        vm = SwitchListVM()
        SwitchManager.shared.registerSwitchesShouldShow()
    }
    
    func testSwitchList() throws {
        vm.refreshData()
        XCTAssertGreaterThan(vm.uncategoryItemList.count, 0)
        XCTAssertGreaterThan(vm.audioItemList.count, 0)
        XCTAssertGreaterThan(vm.cleanupItemList.count, 0)
    }
}
