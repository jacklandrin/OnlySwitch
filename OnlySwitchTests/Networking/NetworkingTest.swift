//
//  NetworkingTest.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import XCTest
@testable import Alamofire
@testable import OnlySwitch

class NetworkingTest:XCTestCase {
    private var presenter:GitHubRepositoryProtocol!
    private var reachabilityManager: NetworkReachabilityManager!
    
    override func setUp() {
        presenter = GitHubMockRespository()
        reachabilityManager = NetworkReachabilityManager(host: "api.github.com")
    }
    
    override func tearDown() {
        presenter = nil
        reachabilityManager = nil
    }
    
    func testCheckUpdate() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }

        let exp = expectation(description: "checkUpdate requestion finished")
        
        presenter.checkUpdate(complete: { result in
            switch result {
            case .success:
                XCTAssertEqual(self.presenter.latestVersion, "2.3.2")
            case let .failure(error):
                XCTAssertThrowsError(error)
            }
            exp.fulfill()
        })
        wait(for: [exp], timeout: 10.0)
    }
    
    func testRequestReleases() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }
        let exp = expectation(description: "releases requestion finished")
        presenter.requestReleases(complete: { result in
            switch result {
            case .success:
                XCTAssertGreaterThan(self.presenter.downloadCount, 0)
                XCTAssertFalse(self.presenter.updateHistoryInfo.isEmpty)
            case let .failure(error):
                XCTAssertThrowsError(error)
            }
            exp.fulfill()
        })
        wait(for: [exp], timeout: 10.0)
    }
    
    func testRequestShortcutsJson() throws {
        guard let reachabilityManager = reachabilityManager, reachabilityManager.isReachable else {
            throw RequestError.notReachable
        }
        let exp = expectation(description: "shortcuts json requestion finished")
        presenter.requestShortcutsJson { result in
            switch result {
            case let .success(list):
                XCTAssertGreaterThan(list.count, 0)
            case let .failure(error):
                XCTAssertThrowsError(error)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10.0)
    }
}
