//
//  NetworkingTest.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import XCTest
@testable import Alamofire

class NetworkingTest:XCTestCase {
    private var presenter:GitHubPresenter!
    private var reachabilityManager: NetworkReachabilityManager!
    
    override func setUpWithError() throws {
        presenter = GitHubPresenter()
        reachabilityManager = NetworkReachabilityManager(host: "api.github.com")
    }
    
    func testCheckUpdate() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }

        let exp = expectation(description: "checkUpdate requestion finished")
        
        presenter.checkUpdate(complete: { success in
            if success {
                XCTAssertEqual(self.presenter.latestVersion, "2.3")
                exp.fulfill()
            } 
        })
        wait(for: [exp], timeout: 10.0)
    }
    
    func testRequestReleases() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }
        let exp = expectation(description: "releases requestion finished")
        presenter.requestReleases(complete: { success in
            if success {
                XCTAssertGreaterThan(self.presenter.downloadCount, 0)
                XCTAssertFalse(self.presenter.updateHistoryInfo.isEmpty)
                exp.fulfill()
            }
        })
        wait(for: [exp], timeout: 10.0)
    }
    
    func testRequestShortcutsJson() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }
        let exp = expectation(description: "shortcuts json requestion finished")
        presenter.requestShortcutsJson(complete: { list in
            guard let list = list else {
                return
            }
            XCTAssertGreaterThan(list.count, 0)
            exp.fulfill()
        })
        wait(for: [exp], timeout: 10.0)
    }
}
