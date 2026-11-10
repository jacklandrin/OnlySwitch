//
//  EvolutionScriptAssistantView.swift
//  OnlySwitch
//

import ComposableArchitecture
import OnlyAgent
import SwiftUI

/// Describe-and-generate: the Only Agent model writes this Evolution's scripts.
struct EvolutionScriptAssistantView: View {
    let store: StoreOf<EvolutionEditorReducer>

    private var generation: EvolutionEditorReducer.Generation { store.generation }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Write scripts with AI".localized(), systemImage: "sparkles")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Describe what this should do…".localized(),
                    text: Binding(
                        get: { generation.prompt },
                        set: { store.send(.generation(.promptChanged($0))) }
                    ),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.send(.generation(.generateTapped)) }
                .disabled(generation.isGenerating)

                if generation.isGenerating {
                    ProgressView().controlSize(.small)
                    Button("Stop".localized()) {
                        store.send(.generation(.stopTapped))
                    }
                } else {
                    Button("Generate".localized()) {
                        store.send(.generation(.generateTapped))
                    }
                    .evolutionProminentButtonStyle()
                    .disabled(generation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = generation.error {
                HStack(spacing: 8) {
                    Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if error == .noModelSelected {
                        Button("Open Only Agent".localized()) {
                            store.send(.generation(.openOnlyAgent))
                        }
                    }
                }
                .font(.callout)
            }

            if let notes = generation.notes {
                Label(notes, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Generated scripts are not run until you test or use them.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .evolutionCard()
        .confirmationDialog(
            "Replace the current scripts?".localized(),
            isPresented: Binding(
                get: { generation.pendingResult != nil },
                set: { if !$0 { store.send(.generation(.cancelReplace)) } }
            )
        ) {
            Button("Replace".localized(), role: .destructive) {
                store.send(.generation(.confirmReplace))
            }
            Button("Cancel".localized(), role: .cancel) {
                store.send(.generation(.cancelReplace))
            }
        } message: {
            Text("The generated scripts will replace what you have written.".localized())
        }
    }

    static func message(for error: EvolutionScriptGenerationError) -> String {
        switch error {
        case .noModelSelected: "Choose a model in Only Agent first.".localized()
        case .emptyReply: "The model returned an empty reply.".localized()
        case .unparseable: "The model's reply couldn't be read. Try again or rephrase.".localized()
        case .incomplete: "The model returned an incomplete script. Try again.".localized()
        case let .declined(reason): reason
        case let .failed(message): message
        }
    }
}
