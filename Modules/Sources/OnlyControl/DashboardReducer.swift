//
//  DashboardReducer.swift
//  Modules
//
//  Created by Jacklandrin on 2024/9/21.
//

import ComposableArchitecture
import Foundation

@Reducer
public struct DashboardReducer {
    @ObservableState
    public struct State: Equatable {
        public var items: [ControlItemViewState] = []
        public init(items: [ControlItemViewState] = []) {
            self.items = items
        }
    }

    public init() {}

    public enum Action: Equatable {
        case moveLocation(IndexSet, Int)
        case onEndedMove
        case didTapItem(String)
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case didTapItem(String)
            case orderChanged
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case let .moveLocation(from, to):
                    state.items.move(fromOffsets: from, toOffset: to)
                    return .none

                case .onEndedMove:
                    state.items = state.items.enumerated().map { index, item in
                        var newItem = item
                        newItem.weight = index
                        return newItem
                    }
                    return .send(.delegate(.orderChanged))

                case let .didTapItem(id):
                    if let item = state.items.first(where: {$0.id == id}), item.controlType != .Button {
                        var newItem = item
                        newItem.status.toggle()
                        state.items = state.items.map { $0.id == id ? newItem : $0 }
                    }

                    return .send(.delegate(.didTapItem(id)))

                case .delegate:
                    return .none
            }
        }
    }
}
