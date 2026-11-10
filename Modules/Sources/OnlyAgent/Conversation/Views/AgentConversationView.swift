//
//  AgentConversationView.swift
//  Modules
//

import ComposableArchitecture
import Defines
import Extensions
import SwiftUI

@available(macOS 26.0, *)
public struct AgentConversationView: View {
    @SwiftUI.Bindable var store: StoreOf<AgentConversationReducer>
    /// Set by the hosting window while it fades out.
    let isClosing: Bool

    @FocusState private var isComposerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomID = "agent-bottom"

    public init(store: StoreOf<AgentConversationReducer>, isClosing: Bool = false) {
        self.store = store
        self.isClosing = isClosing
    }

    public var body: some View {
        VStack(spacing: 0) {
            AgentHeaderView(store: store)
                .appKitWindowDrag()
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(width: Layout.onlyAgentWindowWidth, height: Layout.onlyAgentWindowHeight)
        .glassEffect(in: .rect(cornerRadius: 22))
        .overlay(alignment: .top) { toast }
        .sheet(item: Binding(
            get: { store.saveDraft.map(SaveSheetItem.init) },
            set: { if $0 == nil { store.send(.saveCancelled) } }
        )) { item in
            AgentSaveEvolutionSheet(draft: item.draft, store: store)
        }
        .opacity(isClosing ? 0 : 1)
        .blur(radius: isClosing ? 16 : 0)
        .animation(.smooth(duration: 0.4), value: isClosing)
        .onAppear {
            store.send(.appear)
            isComposerFocused = true
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if store.messages.isEmpty {
                        AgentEmptyStateView(suggestions: store.suggestions, isEnabled: !store.isBusy) { suggestion in
                            store.send(.suggestionTapped(suggestion), animation: .smooth)
                        }
                    }
                    ForEach(store.messages) { message in
                        AgentMessageRow(
                            message: message,
                            isLatest: message.id == store.messages.last?.id,
                            store: store
                        )
                        .id(message.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                    if store.isGenerating {
                        AgentThinkingRow(text: store.thinkingText)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(16)
            }
            .scrollIndicators(.automatic)
            .onChange(of: store.messages.count) {
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: store.isGenerating) {
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Only Agent…".localized(), text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .onSubmit { store.send(.sendTapped, animation: .smooth) }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(in: .rect(cornerRadius: 16))

            if store.isGenerating {
                Button("Stop".localized(), systemImage: "stop.fill") {
                    store.send(.stopGenerating)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("Stop".localized())
            } else {
                Button("Send".localized(), systemImage: "arrow.up") {
                    store.send(.sendTapped, animation: .smooth)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(!store.canSend)
                .help("Send".localized())
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var toast: some View {
        if store.toast == .savedToEvolution {
            Label("Saved to Evolution".localized(), systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.send(.toastDismissed) }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

@available(macOS 26.0, *)
private struct SaveSheetItem: Identifiable {
    let draft: AgentConversationReducer.State.SaveDraft
    var id: UUID { draft.planID }
}

@available(macOS 26.0, *)
#Preview("Conversation") {
    var state = AgentConversationReducer.State(
        currentAIModel: Shared(value: CurrentAIModel(provider: "openai", model: "gpt-5")),
        executionMode: Shared(value: .preview)
    )
    var question = AgentQuestion(id: UUID(), prompt: "Which display should be dimmed?", options: ["Built-in", "External", "All"])
    question.answer = "Built-in"
    state.messages = [
        AgentMessage(id: UUID(), role: .user, content: .text("Dim my screen and turn on dark mode")),
        AgentMessage(id: UUID(), role: .assistant, content: .questions([question], answered: true)),
        AgentMessage(id: UUID(), role: .assistant, content: .plan(AgentPlan(
            id: UUID(),
            title: "Night setup",
            summary: "Turns on dark mode and lowers brightness.",
            steps: [
                AgentScriptStep(id: UUID(), title: "Enable dark mode", kind: .applescript, code: "tell application \"System Events\" to tell appearance preferences to set dark mode to true", status: .succeeded),
                AgentScriptStep(id: UUID(), title: "Lower brightness", kind: .shell, code: "brightness 0.4", status: .failed, error: "command not found: brightness"),
            ]
        ))),
    ]
    return AgentConversationView(store: Store(initialState: state) { AgentConversationReducer() })
}
