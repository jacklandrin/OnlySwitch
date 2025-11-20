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

@available(macOS 26.0, *)
public struct PromptDialogueView: View {
    @FocusState private var promptFocused: Bool
    
    @Perception.Bindable var store: StoreOf<PromptDialogueReducer>
    
    public init(store: StoreOf<PromptDialogueReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            VStack {
                Text("What can AI commander do for you?")
                    .padding(10)
                TextEditor(text: $store.prompt)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 18))
                    .focused($promptFocused)
                    .frame(minWidth: Layout.promptDialogWidth, minHeight: Layout.promptDialogHeight)
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
                
                if !store.isAppleScriptEmpty {
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
                
                HStack {
                    Menu(store.currentAIModel ?? "Models") {
                        ForEach(store.modelTags) { tag in
                            Button {
                                store.send(.selectAIModel(tag.model))
                            } label: {
                                Text(tag.model)
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
            .appKitWindowDrag()
            .glassEffect(in: .rect(cornerRadius: 10.0))
            .cornerRadius(10.0)
            .onAppear {
                store.send(.appear)
                promptFocused = true
            }
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    PromptDialogueView(store: .init(initialState: .init(), reducer: PromptDialogueReducer.init))
}
