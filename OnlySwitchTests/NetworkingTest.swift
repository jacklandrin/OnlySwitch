//
//  NetworkingTest.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import XCTest
@testable import Alamofire

class NetworkingTest:XCTestCase {
    var reachabilityManager = NetworkReachabilityManager(host: "api.github.com")
    func testCheckUpdate() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }

        let exp = expectation(description: "checkUpdate requestion finished")
        let presenter = CheckUpdatePresenter()
        presenter.checkUpdate(complete: { success in
            if success {
                XCTAssertEqual(presenter.latestVersion, "2.2.5")
                exp.fulfill()
            } 
        })
        wait(for: [exp], timeout: 10.0)
    }
}
