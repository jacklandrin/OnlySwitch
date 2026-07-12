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
    @State private var presentedDetailID: String?

    public init(store: StoreOf<DashboardReducer>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ReorderableForeach(store.items.elements, active: $active) { item in
                        ControlItemView(viewState: item)
                            .onTapGesture {
                                handleTap(item)
                            }
                            .popover(isPresented: detailBinding(for: item)) {
                                AuthenticatorControlPopover {
                                    presentedDetailID = nil
                                }
                            }
                            .opacity(item.opacity)
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

    private func handleTap(_ item: ControlItemViewState) {
        switch item.interaction {
            case .performControl:
                store.send(.onTapItem(item.id))
                store.send(.didTapItem(item.id))
            case .presentDetail:
                presentedDetailID = item.id
        }
    }

    private func detailBinding(for item: ControlItemViewState) -> Binding<Bool> {
        Binding(
            get: { presentedDetailID == item.id },
            set: { isPresented in
                if !isPresented {
                    presentedDetailID = nil
                }
            }
        )
    }

}

#Preview {
    DashboardView(store: .init(initialState: .init()) {
        DashboardReducer()
    })
}
