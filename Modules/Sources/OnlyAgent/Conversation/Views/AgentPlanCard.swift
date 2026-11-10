//
//  AgentPlanCard.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct AgentPlanCard: View {
    let plan: AgentPlan
    let store: StoreOf<AgentConversationReducer>

    private var isRunningThisPlan: Bool { store.runningPlanID == plan.id }
    private var isSaved: Bool { store.savedPlanIDs.contains(plan.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    AgentStepRow(
                        index: index,
                        step: step,
                        isEditable: !isRunningThisPlan,
                        onEdit: { code in
                            store.send(.editStepCode(planID: plan.id, stepID: step.id, code: code))
                        }
                    )
                }
            }

            if isRunningThisPlan, let request = store.passwordRequest {
                AgentPasswordPromptView(request: request, store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
        .animation(.smooth, value: plan)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(plan.title.isEmpty ? "Plan".localized() : plan.title, systemImage: "list.bullet.rectangle")
                .font(.headline)
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if isRunningThisPlan {
                Button("Stop".localized(), systemImage: "stop.fill") {
                    store.send(.stopRun)
                }
                .buttonStyle(.glass)
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(plan.hasRun ? "Run again".localized() : "Run".localized(), systemImage: "play.fill") {
                    store.send(.runPlan(plan.id))
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .disabled(store.isBusy)

                if plan.hasFailed {
                    Button("Fix with Only Agent".localized(), systemImage: "wand.and.stars") {
                        store.send(.askToFix(plan.id), animation: .smooth)
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isBusy)
                }
            }

            Spacer()

            if plan.isSucceeded {
                if isSaved {
                    Label("Saved to Evolution".localized(), systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Button("Save as Evolution".localized(), systemImage: "square.and.arrow.down") {
                        store.send(.saveTapped(plan.id))
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isBusy)
                }
            }
        }
    }
}

@available(macOS 26.0, *)
struct AgentStepRow: View {
    let index: Int
    let step: AgentScriptStep
    let isEditable: Bool
    let onEdit: (String) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(step.title.isEmpty ? String(format: "Step %lld".localized(), index + 1) : step.title)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(step.kind == .shell ? "Shell" : "AppleScript")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(index + 1). \(step.title), \(statusDescription)")
            .accessibilityHint(isExpanded ? "Hide script".localized() : "Show script".localized())

            if isExpanded {
                codeEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = step.error, step.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if step.status == .stopped {
                Text("Stopped".localized())
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let output = step.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                Text(output)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(.background.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private var codeEditor: some View {
        TextEditor(text: Binding(get: { step.code }, set: onEdit))
            .font(.callout.monospaced())
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60, maxHeight: 180)
            .padding(6)
            .background(.black.opacity(0.06), in: .rect(cornerRadius: 8))
            .disabled(!isEditable)
            .accessibilityLabel("Script".localized())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .running:
            Image(systemName: "circle.dotted.circle").foregroundStyle(.blue)
                .symbolEffect(.rotate, options: .repeating)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .stopped:
            Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var statusDescription: String {
        switch step.status {
        case .pending: "Pending".localized()
        case .running: "Running".localized()
        case .succeeded: "Succeeded".localized()
        case .failed: "Failed".localized()
        case .stopped: "Stopped".localized()
        case .skipped: "Skipped".localized()
        }
    }
}
