//
//  BackNoisesSettingReducerTests.swift
//  OnlySwitchTests
//
//  Created by Leon on 2023/12/15.
//

import XCTest
import ComposableArchitecture
@testable import OnlySwitch

@MainActor
final class BackNoisesSettingReducerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSelectTrack() async {
        let store = TestStore(initialState: BackNoisesSettingReducer.State()) {
            BackNoisesSettingReducer()
        }
        
        let task = await store.send(.task)

        // receive action but state has no changes
        await store.receive(\.currentTrackUpdated)
        
        await store.send(.selectTrack(index: 3))

        await store.receive(\.currentTrackUpdated) {
            $0.currentTrack = "Meadow Birds"
        }
        
        await store.send(.selectTrack(index: 7))
        
        await store.receive(\.currentTrackUpdated) {
            $0.currentTrack = "Harbor Wave"
        }
        
        await store.send(.selectTrack(index: 0))
        
        await store.receive(\.currentTrackUpdated) {
            $0.currentTrack = "White Noise"
        }
        
        await task.cancel()
    }
}
