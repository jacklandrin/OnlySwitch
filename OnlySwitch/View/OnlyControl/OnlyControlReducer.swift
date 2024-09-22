//
//  OnlyControl.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/9/21.
//

import ComposableArchitecture
import OnlyControl

@Reducer
struct OnlyControlReducer {
    @ObservableState
    struct State: Equatable {
        var dashboard: DashboardReducer.State = .init()
        var blurRadius: CGFloat = 20
        var opacity: Double = 0
    }

    enum Action: Equatable {
        case task
        case showControl
        case hideControl
        case dashboardAction(DashboardReducer.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboardAction) {
            DashboardReducer()
        }

        Reduce { state, action in
            switch action {
                case .task:
                    state.dashboard.items = (1...20).map { ControlItemViewState.preview(id: $0) }
                    return .none
                    
                case .showControl:
                    state.blurRadius = 0
                    state.opacity = 1
                    return .none

                case .hideControl:
                    state.blurRadius = 20
                    state.opacity = 0
                    return .none

                case .dashboardAction:
                    return .none
            }
        }
    }
}
