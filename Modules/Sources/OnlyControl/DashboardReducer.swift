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
        public var items: IdentifiedArrayOf<ControlItemViewState> = []
        public init(items: IdentifiedArrayOf<ControlItemViewState> = []) {
            self.items = items
        }
    }

    public init() {}

    public enum Action: Equatable {
        case moveLocation(IndexSet, Int)
        case onEndedMove
        case onTapItem(String)
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
                    let array = state.items.elements
                    let newArray = array.enumerated().map { index, item in
                        var newItem = item
                        newItem.weight = index
                        return newItem
                    }
                    state.items = IdentifiedArray(uniqueElements: newArray)
                    return .send(.delegate(.orderChanged))

                case let .onTapItem(id):
                    if let item = state.items.first(where: {$0.id == id}) {
                        var newItem = item
                        newItem.opacity = 0.7
                        state.items = IdentifiedArray(uniqueElements: state.items.map { $0.id == id ? newItem : $0 })
                    }
                    return .none

                case let .didTapItem(id):
                    if let item = state.items.first(where: {$0.id == id}), item.controlType != .Button {
                        var newItem = item
                        newItem.status.toggle()
                        newItem.opacity = 1.0
                        state.items = IdentifiedArray(uniqueElements: state.items.map { $0.id == id ? newItem : $0 })
                    }

                    return .send(.delegate(.didTapItem(id)))

                case .delegate:
                    return .none
            }
        }
    }
}
