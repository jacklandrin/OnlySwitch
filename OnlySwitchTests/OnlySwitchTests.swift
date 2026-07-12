//
//  OnlySwitchTests.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/18.
//

import XCTest
@testable import OnlySwitch

class OnlySwitchTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    @MainActor
    func testDimScreenSliderPublishesRoundedValue() {
        let viewModel = DimScreenSettingVM()

        viewModel.sliderValue = 0.73

        XCTAssertEqual(viewModel.sliderValue, 0.7)
        XCTAssertEqual(Preferences.shared.dimScreenPercent, 0.7)
    }

    @MainActor
    func testAppearanceNotificationSeesNewValue() {
        let originalAppearance = Preferences.shared.currentAppearance
        let newAppearance = originalAppearance == SwitchListAppearance.single.rawValue
            ? SwitchListAppearance.dual.rawValue
            : SwitchListAppearance.single.rawValue
        var observedAppearance: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .shouldHidePopover,
            object: nil,
            queue: .main
        ) { _ in
            observedAppearance = Preferences.shared.currentAppearance
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            Preferences.shared.currentAppearance = originalAppearance
        }

        Preferences.shared.currentAppearance = newAppearance

        XCTAssertEqual(observedAppearance, newAppearance)
    }

    
    
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
