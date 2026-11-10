//
//  EvolutionGalleryItemView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import SwiftUI

/// A gallery card: icon, name, description, author and Add.
struct EvolutionGalleryItemView: View {
    let store: StoreOf<EvolutionGalleryItemReducer>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: store.item.evolution.displayIconName)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                Spacer()
                Text(store.item.evolution.controlType == .Button ? "Button".localized() : "Switch".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(store.item.evolution.name)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(store.item.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .help(store.item.description)
            HStack {
                Text(verbatim: "@\(store.item.author)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if store.item.installed {
                    Label("Added".localized(), systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Button("Add".localized(), systemImage: "plus") {
                        store.send(.install)
                    }
                    .evolutionProminentButtonStyle()
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .evolutionCard()
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    EvolutionGalleryItemView(
        store: Store(
            initialState: EvolutionGalleryItemReducer.State(
                item: EvolutionGalleryItem(evolution: EvolutionItem(name: "Dark Mode"))
            )
        ) {
            EvolutionGalleryItemReducer()
        }
    )
    .frame(width: 240)
}
#endif
