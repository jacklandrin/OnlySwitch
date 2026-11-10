//
//  AgentHeaderView.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct AgentHeaderView: View {
    @SwiftUI.Bindable var store: StoreOf<AgentConversationReducer>

    /// Same provider order as the previous Only Agent model menu.
    private static let providerSections: [(ModelProvider, String)] = [
        (.ollama, "Ollama"),
        (.openai, "OpenAI"),
        (.codex, "Codex"),
        (.gemini, "Gemini"),
        (.claude, "Claude"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            Label("Only Agent".localized(), systemImage: "sparkles")
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.multicolor)

            Spacer(minLength: 8)

            modelMenu

            Picker("Execution".localized(), selection: $store.executionMode.sending(\.setExecutionMode)) {
                Text("Preview first".localized()).tag(AgentExecutionMode.preview)
                Text("Run directly".localized()).tag(AgentExecutionMode.direct)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Choose whether generated scripts run right away or wait for you to review them".localized())

            Button("New conversation".localized(), systemImage: "square.and.pencil") {
                store.send(.newConversation, animation: .smooth)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(store.messages.isEmpty)
            .help("New conversation".localized())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(Self.providerSections, id: \.0) { provider, title in
                if let models = store.modelTags[provider], !models.isEmpty {
                    Section(title) {
                        ForEach(models, id: \.self) { model in
                            Button {
                                store.send(.selectAIModel(provider: provider, model: model))
                            } label: {
                                if store.currentAIModel == CurrentAIModel(provider: provider.rawValue, model: model) {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(store.currentAIModel?.model ?? "Models".localized(), systemImage: "cpu")
                .lineLimit(1)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("Model".localized())
    }
}
