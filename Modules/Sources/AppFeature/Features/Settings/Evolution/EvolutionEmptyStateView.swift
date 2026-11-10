//
//  EvolutionEmptyStateView.swift
//  OnlySwitch
//

import ComposableArchitecture
import SwiftUI

/// Shown when there are no Evolutions: three ways to get the first one.
struct EvolutionEmptyStateView: View {
    let store: StoreOf<EvolutionReducer>

    var body: some View {
        ContentUnavailableView {
            Label("No Evolutions yet".localized(), systemImage: "wand.and.rays")
        } description: {
            Text("Build your own switches and buttons with Shell or AppleScript.".localized())
        } actions: {
            HStack {
                Button("New Evolution".localized(), systemImage: "plus") {
                    store.send(.newTapped)
                }
                .evolutionProminentButtonStyle()
                Button("Browse Gallery".localized(), systemImage: "square.grid.2x2") {
                    store.send(.tabChanged(.gallery))
                }
                if store.isOnlyAgentAvailable {
                    Button("Create with Only Agent".localized(), systemImage: "sparkles") {
                        store.send(.openOnlyAgent)
                    }
                }
            }
        }
    }
}
