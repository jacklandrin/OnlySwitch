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
                Text("What can AI commander do for you?")
                    .padding(10)
                
                promptEditor
                    
                promptActionView
                
                if !store.isAppleScriptEmpty {
                    separatorView
                    
                    appleScriptEditor
                }
                
                executeActionView
                
                statusInfoView
                
                bottomBar
            }
            .appKitWindowDrag()
            .glassEffect(in: .rect(cornerRadius: 10.0))
            .cornerRadius(10.0)
            .onAppear {
                store.send(.appear)
                promptFocused = true
            }
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
            Menu(store.currentModelName ?? "Models") {
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
            }
            .menuIndicator(.visible)
            Spacer()
            Toggle("Agent Mode", isOn: $store.isAgentMode)
                .disabled(!store.isAppleScriptEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

@available(macOS 26.0, *)
#Preview {
    PromptDialogueView(store: .init(initialState: .init(), reducer: PromptDialogueReducer.init))
}
