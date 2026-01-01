//
//  EvolutionGalleryItemView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import SwiftUI

struct EvolutionGalleryItemView: View {
    
    let store: StoreOf<EvolutionGalleryItemReducer>

    init(store: StoreOf<EvolutionGalleryItemReducer>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack {
                HStack {
                    Image(
                        systemName: store.item.evolution.iconName ?? (
                            store.item.evolution.controlType == .Switch
                            ? "lightswitch.on.square"
                            : "button.programmable.square.fill"
                        )
                    )
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)

                    Spacer()
                    Button {
                        store.send(.install)
                    } label: {
                        Image(systemName: store.item.installed ? "checkmark.circle.fill" : "plus.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.item.installed)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer(minLength: 10)
                Text(store.item.evolution.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
                Spacer()
                HStack {
                    Spacer()
                    Text("@\(store.item.author)")
                        .foregroundColor(.white)
                        .font(.system(size: 10))
                }
                .padding(.trailing, 10)
                .padding(.bottom, 5)
            }
            .frame(width: 140, height: 100)
            .background(Color(.themeFountainBlue))
            .help(store.item.description)
            .cornerRadius(10)
        }
    }
}

#if DEBUG
#Preview {
    EvolutionGalleryItemView(
        store: Store(
            initialState: EvolutionGalleryItemReducer.State(
                item: EvolutionGalleryItem(
                    evolution: EvolutionItem()
                )
            )
        ) {
            EvolutionGalleryItemReducer()
        }
    )
}
#endif
