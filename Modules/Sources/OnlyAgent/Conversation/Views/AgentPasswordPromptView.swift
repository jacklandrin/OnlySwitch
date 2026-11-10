//
//  AgentPasswordPromptView.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

/// Inline prompt shown when sudo asks for the administrator password.
/// The typed password lives only in this view until it is submitted.
@available(macOS 26.0, *)
struct AgentPasswordPromptView: View {
    let request: AgentPasswordRequest
    let store: StoreOf<AgentConversationReducer>

    @State private var password = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Administrator password required".localized(), systemImage: "lock.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("The running step asked for your password. It is passed only to sudo for this step and is never saved or sent to the model.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SecureField(request.prompt.isEmpty ? "Password".localized() : request.prompt, text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(submit)
                Button("Cancel".localized(), role: .cancel) {
                    password = ""
                    store.send(.passwordCancelled)
                }
                Button("Continue".localized(), action: submit)
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .disabled(password.isEmpty)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        .onAppear { isFocused = true }
        .onChange(of: request.id) {
            password = ""
            isFocused = true
        }
        .onDisappear { password = "" }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        let value = password
        password = ""
        store.send(.passwordSubmitted(value))
    }
}
