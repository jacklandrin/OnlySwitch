//
//  PromptDialogueView.swift
//  Modules
//
//  Created by Bo Liu on 16.11.25.
//

import ComposableArchitecture
import Defines
import Design
import Extensions
import SwiftUI
import SwiftUIIntrospect
import AppKit

@available(macOS 26.0, *)
public struct PromptDialogueView: View {
    @FocusState private var promptFocused: Bool
    @State private var promptHeight: CGFloat = Layout.promptDialogHeight
    @GestureState private var dragOffset: CGFloat = 0
    
    @Perception.Bindable var store: StoreOf<PromptDialogueReducer>
    
    public init(store: StoreOf<PromptDialogueReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack {
                Text("What can AI commander do for you?".localized())
                    .padding(10)
                
                promptEditor
                    
                promptActionView
                
                if !store.isAppleScriptEmpty && !store.isMultiStepMode {
                    separatorView
                    
                    appleScriptEditor
                }
                
                // Multi-step execution plan view
                if store.isMultiStepMode, let plan = store.executionPlan {
                    executionPlanView(plan: plan)
                }
                
                executeActionView
                
                statusInfoView
                
                bottomBar
            }
            .sheet(isPresented: $store.showPlanPreview) {
                planPreviewModal
            }
            .appKitWindowDrag()
            .glassEffect(in: .rect(cornerRadius: 10.0))
            .cornerRadius(10.0)
            .opacity(store.opacity)
            .blur(radius: store.blurRadius)
            .onAppear {
                store.send(.appear)
                promptFocused = true
            }
            .animation(.interactiveSpring(duration: 0.5), value: store.opacity)
        }
    }
    
    private var promptEditor: some View {
        TextEditor(text: $store.prompt)
            .scrollContentBackground(.hidden)
            .font(.system(size: 18))
            .focused($promptFocused)
            .frame(minWidth: Layout.promptDialogWidth)
            .frame(height: max(40, promptHeight + dragOffset))
            .opacity(0.85)
            .overlay {
                if store.isPromptEmpty {
                    VStack {
                        HStack {
                            Text("e.g. Switch to dark mode")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.leading, 8)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.05))
            )
            .padding(.horizontal, 10)
    }
    
    private var promptActionView: some View {
        HStack {
            Spacer()
            if store.isGenerating {
                AppKitProgressView()
                    .scaleEffect(0.6)
            } else {
                Button {
                    store.send(.sendPrompt)
                } label: {
                    Image(systemName: "arrowshape.up.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(store.sendButtonDisabled)
            }
        }
        .padding(.trailing, 10)
    }
    
    private var separatorView: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { _ in
                Circle()
                    .fill(Color.secondary.opacity(0.9))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, transaction in
                    state = value.translation.height
                }
                .onEnded { value in
                    promptHeight = max(40, promptHeight + value.translation.height)
                }
        )
        .padding(.horizontal, 10)
    }
    
    private var appleScriptEditor: some View {
        TextEditor(text: $store.appleScript)
            .scrollContentBackground(.hidden)
            .font(.system(size: 18))
            .opacity(0.85)
            .frame(minHeight: 60)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.05))
            )
            .padding(.horizontal, 10)
            .introspect(.textEditor, on: .macOS(.v26)) { textView in
                textView.isEditable = !store.isAgentMode
            }
    }
    
    private var executeActionView: some View {
        HStack {
            Spacer()
            if store.shouldShowExecuteButton {
                Button {
                    store.send(.executeAppleScript)
                } label: {
                    Image(systemName: "play.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            } else if store.isExecuting {
                AppKitProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.trailing, 10)
    }
    
    @ViewBuilder
    private var statusInfoView: some View {
        if let isSuccess = store.isSuccess {
            HStack {
                if isSuccess {
                    Text("✅")
                } else {
                    Text("❌ \(store.errorMessage ?? "")")
                }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
    }
    
    private var bottomBar: some View {
        HStack {
            Menu(store.currentModelName ?? "Models".localized()) {
                if let ollamaModels = store.modelTags[.ollama] {
                    Text("Ollama")
                        .foregroundStyle(.secondary)
                    ForEach(ollamaModels, id: \.self) { model in
                        Button {
                            store.send(.selectAIModel(provider: ModelProvider.ollama.rawValue, model: model))
                        } label: {
                            Text(model)
                        }
                    }
                }
                if let openAIModels = store.modelTags[.openai] {
                    Text("OpenAI")
                        .foregroundStyle(.secondary)
                    ForEach(openAIModels, id: \.self) { model in
                        Button {
                            store.send(.selectAIModel(provider: ModelProvider.openai.rawValue, model: model))
                        } label: {
                            Text(model)
                        }
                    }
                }
                if let geminiModels = store.modelTags[.gemini] {
                    Text("Gemini")
                        .foregroundStyle(.secondary)
                    ForEach(geminiModels, id: \.self) { model in
                        Button {
                            store.send(.selectAIModel(provider: ModelProvider.gemini.rawValue, model: model))
                        } label: {
                            Text(model)
                        }
                    }
                }
            }
            .menuIndicator(.visible)
            Spacer()
            Toggle("Agent Mode".localized(), isOn: $store.isAgentMode)
                .disabled(store.agentToggleDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private func executionPlanView(plan: [ExecutionStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Execution Plan")
                    .font(.headline)
                Spacer()
                if store.isPlanning {
                    AppKitProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text("\(plan.filter { $0.status == .completed }.count)/\(plan.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan) { step in
                        StepRowView(step: step, isCurrent: step.stepNumber == store.currentStepIndex + 1)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: 200)
        }
        .padding(.vertical, 8)
    }
    
    private var planPreviewModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Execution Plan Preview")
                .font(.title2)
                .fontWeight(.bold)
            
            if let plan = store.executionPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(plan) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Step \(step.stepNumber)")
                                        .font(.headline)
                                    Spacer()
                                }
                                Text(step.description)
                                    .font(.body)
                                if let expected = step.expectedOutcome {
                                    Text("Expected: \(expected)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    store.send(.cancelExecution)
                }
                Button("Approve & Execute") {
                    store.send(.approvePlan)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
}

@available(macOS 26.0, *)
private struct StepRowView: View {
    let step: ExecutionStep
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text("\(step.stepNumber).")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(step.description)
                .font(.caption)
                .lineLimit(1)
            
            Spacer()
            
            if isCurrent {
                AppKitProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isCurrent ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch step.status {
        case .pending:
            return .gray
        case .executing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    PromptDialogueView(store: .init(initialState: .init(), reducer: PromptDialogueReducer.init))
}
