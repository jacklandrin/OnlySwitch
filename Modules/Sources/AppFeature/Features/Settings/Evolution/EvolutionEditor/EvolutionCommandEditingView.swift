//
//  EvolutionCommandEditingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import ComposableArchitecture
import ScriptEditor
import SwiftUI

/// One script of an Evolution: language, highlighted code, Test and its result.
struct EvolutionCommandEditingView: View {
    let store: StoreOf<EvolutionCommandEditingReducer>
    /// The script is the same as the saved one, so it doesn't need a new test.
    let isUnchanged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if store.command.commandType == .status {
                Text("OnlySwitch runs this to read the current state.".localized())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScriptCodeEditor(
                text: Binding(
                    get: { store.command.commandString },
                    set: { store.send(.editCommand($0)) }
                ),
                language: store.command.executeType == .shell ? .shell : .applescript,
                placeholder: placeholder,
                accessibilityLabel: store.command.commandType.scriptAccessibilityLabel
            )
            .frame(minHeight: 90, idealHeight: 120, maxHeight: 220)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.1)) }

            if store.command.executeType == .shell {
                Text("Shell scripts run inside AppleScript's do shell script, so write \\\" for a double quote.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if store.command.commandType == .status {
                statusOutput
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .evolutionCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(store.command.commandType.editorTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker(
                "Language".localized(),
                selection: Binding(
                    get: { store.command.executeType },
                    set: { store.send(.changeExecuteType($0)) }
                )
            ) {
                Text("Shell".localized()).tag(CommandExecuteType.shell)
                Text("AppleScript".localized()).tag(CommandExecuteType.applescript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 8)

            EvolutionTestBadge(status: store.command.debugStatus, isUnchanged: isUnchanged)

            Button {
                store.send(.testTapped)
            } label: {
                if store.isTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Test".localized(), systemImage: "play.fill")
                }
            }
            .disabled(store.isTesting || store.command.commandString.isEmpty)
            .help("Runs this script now on your Mac.".localized())
        }
    }

    @ViewBuilder
    private var statusOutput: some View {
        if let output = store.lastOutput {
            HStack(spacing: 6) {
                Text("Last output:".localized())
                    .foregroundStyle(.secondary)
                Text(output.isEmpty ? "(empty)".localized() : output)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .font(.callout)
        }
        HStack {
            TextField(
                "Output when on".localized(),
                text: Binding(
                    get: { store.command.trueCondition ?? "" },
                    set: { store.send(.editTrueCondition($0)) }
                ),
                prompt: Text("e.g. 1 or true".localized())
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            Button("Use last output".localized()) {
                store.send(.useLastOutput)
            }
            .disabled(store.lastOutput == nil)
        }
        Text("The switch shows as on when the output equals this value exactly.".localized())
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var placeholder: String {
        store.command.executeType == .shell
            ? "defaults write com.apple.dock autohide -bool true; killall Dock"
            : "tell application \"Finder\" to activate"
    }
}

/// Whether a script passed its last test, failed, or still needs one.
struct EvolutionTestBadge: View {
    let status: CommandDebugStatus
    let isUnchanged: Bool

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .help(help)
    }

    private var title: String {
        switch status {
        case .success: "Passed".localized()
        case .failed: "Failed".localized()
        case .unknow: isUnchanged ? "Unchanged".localized() : "Not tested".localized()
        }
    }

    private var symbol: String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unknow: isUnchanged ? "checkmark.seal" : "circle.dashed"
        }
    }

    private var color: Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .unknow: isUnchanged ? .secondary : .orange
        }
    }

    private var help: String {
        switch status {
        case .unknow where isUnchanged:
            "This script hasn't changed since it was saved.".localized()
        case .unknow:
            "Test this script before saving.".localized()
        default:
            title
        }
    }
}
