//
//  EvolutionRowView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture
import SwiftUI

/// An Evolution in the sidebar: icon, name, type, and whether it's in the menu.
struct EvolutionRowView: View {
    let store: StoreOf<EvolutionRowReducer>

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: store.evolution.displayIconName)
                .font(.system(size: 15))
                .frame(width: 22, height: 22)
                .foregroundStyle(store.evolution.active ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.evolution.name)
                    .lineLimit(1)
                Text(store.evolution.controlType == .Button ? "Button".localized() : "Switch".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle(
                String(format: "Show %@ in the menu".localized(), store.evolution.name),
                isOn: Binding(
                    get: { store.evolution.active },
                    set: { store.send(.setActive($0)) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Show in the OnlySwitch menu".localized())
        }
        .padding(.vertical, 2)
    }
}
