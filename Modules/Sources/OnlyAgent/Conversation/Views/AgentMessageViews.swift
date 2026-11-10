//
//  AgentMessageViews.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct AgentMessageRow: View {
    let message: AgentMessage
    let isLatest: Bool
    let store: StoreOf<AgentConversationReducer>

    var body: some View {
        switch message.content {
        case let .text(text):
            if message.role == .user {
                AgentBubble(text: text, isUser: true)
            } else {
                AgentBubble(text: text, isUser: false)
            }
        case .fixRequest:
            AgentBubble(text: "Please fix the failed step".localized(), isUser: true)
        case let .error(text):
            AgentNoticeView(text: text, systemImage: "exclamationmark.triangle.fill", tint: .red)
        case let .notice(notice):
            switch notice {
            case .selectModel:
                AgentNoticeView(text: "Select a model to start".localized(), systemImage: "cpu", tint: .orange)
            }
        case let .questions(questions, answered):
            AgentQuestionCard(
                messageID: message.id,
                questions: questions,
                isActive: isLatest && !answered,
                store: store
            )
        case let .plan(plan):
            AgentPlanCard(plan: plan, store: store)
        }
    }
}

@available(macOS 26.0, *)
struct AgentBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isUser ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.6)),
                    in: .rect(cornerRadius: 14)
                )
            if !isUser { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isUser ? "You".localized() : "Only Agent".localized())
        .accessibilityValue(text)
    }
}

@available(macOS 26.0, *)
struct AgentNoticeView: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(.callout)
        .padding(10)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

@available(macOS 26.0, *)
struct AgentEmptyStateView: View {
    let suggestions: [AgentSuggestion]
    let isEnabled: Bool
    let onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
                .symbolEffect(.breathe, options: .nonRepeating)
                .accessibilityHidden(true)
            Text("Describe a system change…".localized())
                .font(.title3.weight(.semibold))
            Text("Only Agent asks when something is unclear, then writes scripts you can preview, run and save as an Evolution button.".localized())
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    let title = suggestion.rawValue.localized()
                    Button(title) {
                        onSuggestion(title)
                    }
                    .buttonStyle(.glass)
                    .disabled(!isEnabled)
                    .transition(.opacity)
                }
            }
            .padding(.top, 4)
            .animation(.smooth, value: suggestions)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
