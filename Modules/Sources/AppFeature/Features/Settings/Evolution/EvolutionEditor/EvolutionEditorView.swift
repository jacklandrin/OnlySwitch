//
//  EvolutionEditorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import KeyboardShortcuts
import SwiftUI
import Switches
import Utilities

/// The inline editor for one Evolution: identity, AI assistant, scripts,
/// shortcut, and a footer with what's still needed and Save.
struct EvolutionEditorView: View {
    let store: StoreOf<EvolutionEditorReducer>
    @ObservedObject private var langManager = LanguageManager.sharedManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    if store.generation.isAvailable {
                        EvolutionScriptAssistantView(store: store)
                    }
                    ForEach(store.scope(state: \.commandStates, action: \.commandAction)) { commandStore in
                        EvolutionCommandEditingView(
                            store: commandStore,
                            isUnchanged: store.state.isUnchanged(commandStore.command)
                        )
                    }
                    shortcut
                }
                .padding(20)
            }
            Divider()
            EvolutionEditorFooter(store: store)
        }
        .toast(
            isPresenting: Binding(
                get: { store.showSaveError },
                set: { if !$0 { store.send(.dismissSaveError) } }
            ),
            alert: {
                AlertToast(displayMode: .alert, type: .error(.red), title: "Save commands failed.".localized())
            }
        )
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    store.send(.toggleIconPicker(!store.showIconPicker))
                } label: {
                    Image(systemName: store.evolution.displayIconName)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("Choose an icon".localized())
                .accessibilityLabel("Choose an icon".localized())
                .popover(
                    isPresented: Binding(
                        get: { store.showIconPicker },
                        set: { store.send(.toggleIconPicker($0)) }
                    )
                ) {
                    EvolutionIconPicker(selected: store.evolution.displayIconName) { name in
                        store.send(.selectIcon(name))
                    }
                }

                TextField(
                    "Name".localized(),
                    text: Binding(
                        get: { store.evolution.name },
                        set: { store.send(.changeName($0)) }
                    ),
                    prompt: Text("Name".localized())
                )
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            }

            Picker(
                "Type".localized(),
                selection: Binding(
                    get: { store.evolution.controlType },
                    set: { store.send(.changeType($0)) }
                )
            ) {
                Text("Switch".localized()).tag(ControlType.Switch)
                Text("Button".localized()).tag(ControlType.Button)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(
                store.evolution.controlType == .Button
                    ? "Button: runs a script once.".localized()
                    : "Switch: turns something on and off and shows its current state.".localized()
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .evolutionCard()
    }

    private var shortcut: some View {
        HStack {
            Text("Keyboard shortcut".localized())
            Spacer()
            if store.isNew {
                Text("Save first to assign a shortcut.".localized())
                    .foregroundStyle(.secondary)
            } else {
                KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name(store.evolution.id.uuidString))
                    .environment(\.locale, .init(identifier: langManager.currentLang))
            }
        }
        .padding(16)
        .evolutionCard()
    }
}

/// What still blocks saving, plus Revert and Save.
struct EvolutionEditorFooter: View {
    let store: StoreOf<EvolutionEditorReducer>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            let missing = store.state.missingRequirements
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(missing, id: \.self) { requirement in
                        Label(Self.message(for: requirement), systemImage: "exclamationmark.circle")
                    }
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }
            Spacer(minLength: 12)
            Button("Revert".localized()) {
                store.send(.revert)
            }
            .disabled(!store.state.isDirty || store.isSaving)
            Button {
                store.send(.save)
            } label: {
                if store.isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save".localized())
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .evolutionProminentButtonStyle()
            .disabled(!store.state.canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    static func message(for requirement: EvolutionEditorReducer.Requirement) -> String {
        switch requirement {
        case .name:
            "Enter a name".localized()
        case let .script(type):
            String(format: "Write the “%@” script".localized(), type.editorTitle)
        case let .test(type):
            String(format: "Test the “%@” script".localized(), type.editorTitle)
        case .statusOnOutput:
            "Set “Output when on”".localized()
        }
    }
}

#Preview {
    EvolutionEditorView(
        store: Store(initialState: EvolutionEditorReducer.State(generationAvailable: true)) {
            EvolutionEditorReducer()
        }
    )
    .frame(width: 560, height: 720)
}
