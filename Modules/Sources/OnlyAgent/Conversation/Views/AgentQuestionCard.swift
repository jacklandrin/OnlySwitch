//
//  AgentQuestionCard.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct AgentQuestionCard: View {
    let messageID: UUID
    let questions: [AgentQuestion]
    let isActive: Bool
    let store: StoreOf<AgentConversationReducer>

    private var canContinue: Bool {
        isActive && !store.isBusy
            && questions.allSatisfy { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("A few questions first".localized(), systemImage: "questionmark.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(questions) { question in
                questionView(question)
            }

            if isActive {
                HStack {
                    Spacer()
                    Button("Continue".localized(), systemImage: "arrow.right") {
                        store.send(.submitAnswers(messageID: messageID), animation: .smooth)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
        .opacity(isActive ? 1 : 0.75)
    }

    @ViewBuilder
    private func questionView(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if isActive {
                if !question.options.isEmpty {
                    AgentChipFlow(spacing: 6) {
                        ForEach(question.options, id: \.self) { option in
                            let isSelected = question.answer == option
                            Button(option) {
                                store.send(.answerChanged(messageID: messageID, questionID: question.id, answer: option), animation: .snappy)
                            }
                            .buttonStyle(.glass)
                            .tint(isSelected ? .accentColor : nil)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                TextField(
                    "Your answer".localized(),
                    text: Binding(
                        get: { question.answer },
                        set: { store.send(.answerChanged(messageID: messageID, questionID: question.id, answer: $0)) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canContinue {
                        store.send(.submitAnswers(messageID: messageID), animation: .smooth)
                    }
                }
            } else if !question.answer.isEmpty {
                Label(question.answer, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Wraps option chips onto multiple lines.
@available(macOS 26.0, *)
struct AgentChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
