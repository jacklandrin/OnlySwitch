//
//  DashboardView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/7/7.
//

import ComposableArchitecture
import Defines
import Reorderable
import SwiftUI

public struct DashboardView: View {
    let store: StoreOf<DashboardReducer>
    let columns = [
        GridItem(.adaptive(minimum: 85, maximum: 180), alignment: .leading)
        ]

    @State private var active: ControlItemViewState?
    @State private var hasChangedLocation = false

    public init(store: StoreOf<DashboardReducer>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ReorderableForeach(store.items, active: $active) { item in
                        ControlItemView(viewState: item)
                            .onTapGesture {
                                store.send(.didTapItem(item.id))
                            }
                    } preview: { item in
                        ControlItemView(viewState: item)
                            .frame(width: 100, height: 100)
                            .scaleEffect(1.1)
                    } moveAction: { from, to in
                        store.send(.moveLocation(from, to))
                    } onEnded: {
                        store.send(.onEndedMove)
                    }
                }
                .padding()
                .animation(.default, value: store.items)
            }
            .reorderableForEachContainer(active: $active) {
                store.send(.onEndedMove)
            }
            .frame(width: 760, height: 340)
        }
    }

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: 20)
    }
}

#Preview {
    DashboardView(store: .init(initialState: .init()) {
        DashboardReducer()
    })
}
