//
//  AgentSaveEvolutionSheet.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct AgentSaveEvolutionSheet: View {
    let draft: AgentConversationReducer.State.SaveDraft
    let store: StoreOf<AgentConversationReducer>

    @FocusState private var isNameFocused: Bool

    private var canSave: Bool {
        !draft.isSaving && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Save as Evolution".localized(), systemImage: "square.and.arrow.down")
                .font(.headline)
            Text("The steps are saved as one Evolution button that you can run from the menu bar.".localized())
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "Evolution button name".localized(),
                text: Binding(get: { draft.name }, set: { store.send(.saveNameChanged($0)) })
            )
            .textFieldStyle(.roundedBorder)
            .focused($isNameFocused)
            .onSubmit {
                if canSave { store.send(.saveConfirmed) }
            }

            if let error = draft.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel".localized(), role: .cancel) {
                    store.send(.saveCancelled)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    store.send(.saveConfirmed)
                } label: {
                    if draft.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save".localized())
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isNameFocused = true }
    }
}
