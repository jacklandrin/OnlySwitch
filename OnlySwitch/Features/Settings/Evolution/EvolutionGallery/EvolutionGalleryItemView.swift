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
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack {
                HStack {
                    Image(
                        systemName: viewStore.item.evolution.iconName ?? (
                            viewStore.item.evolution.controlType == .Switch
                            ? "lightswitch.on.square"
                            : "button.programmable.square.fill"
                        )
                    )
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)

                    Spacer()
                    Button(
                        action: {
                            viewStore.send(.install)
                    }
                    ) {
                        Image(systemName: viewStore.item.installed ? "checkmark.circle.fill" : "plus.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewStore.item.installed)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Spacer(minLength: 10)
                Text(viewStore.item.evolution.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
                Spacer()
                HStack {
                    Spacer()
                    Text("@\(viewStore.item.author)")
                        .foregroundColor(.white)
                        .font(.system(size: 10))
                }
                .padding(.trailing, 10)
                .padding(.bottom, 5)
            }
            .frame(width: 140, height: 100)
            .background(
                LinearGradient(
                    gradient: Gradient(
                        stops: [
                            Gradient.Stop(color: Color(.themePurple), location: 0.1),
                            Gradient.Stop(color: Color(.themePink), location: 0.4),
                            Gradient.Stop(color: Color(.themeGreen), location: 0.7)
                        ]
                    ),
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .blur(radius: 4)
            )
            .help(viewStore.item.description)
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
