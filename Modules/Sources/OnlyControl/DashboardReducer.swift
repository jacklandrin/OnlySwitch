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
        case didTapItem(Int)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case let .moveLocation(from, to):
                    state.items.move(fromOffsets: from, toOffset: to)
                    return .none

                case let .didTapItem(id):
                    if let item = state.items.first(where: {$0.id == id}) {
                        var newItem = item
                        newItem.status.toggle()
                        state.items = state.items.map { $0.id == id ? newItem : $0 }
                    }

                    return .none
            }
        }
    }
}
