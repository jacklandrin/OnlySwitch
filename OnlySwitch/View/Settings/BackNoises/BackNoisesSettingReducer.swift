//
//  BackNoisesSettingReducer.swift
//  OnlySwitch
//
//  Created by Leon on 2023/12/15.
//

import Foundation
import ComposableArchitecture
import Combine

@Reducer
struct BackNoisesSettingReducer {
    struct State: Equatable {
        var trackList:[String] {
            BackNoisesTrackManager.shared.trackList.map { $0.rawValue }
        }
        var currentTrack:String = BackNoisesTrackManager.shared.currentTrack.rawValue
    }
    
    enum Action: Equatable {
        case task
        case currentTrackUpdated(BackNoisesTrackManager.Tracks)
        case selectTrack(index: Int)
    }
        
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    for await currentTrack in BackNoisesTrackManager.shared.$currentTrack.values {
                        await send(.currentTrackUpdated(currentTrack))
                    }
                }
                
            case let .currentTrackUpdated(currentTrack):
                state.currentTrack = currentTrack.rawValue
                return .none
                
            case let .selectTrack(index: index):
                let track = BackNoisesTrackManager.shared.trackList[index]
                BackNoisesTrackManager.shared.currentTrack = track
                return .none
            }
        }
    }
}

