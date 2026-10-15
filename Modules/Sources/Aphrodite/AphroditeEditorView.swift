import ComposableArchitecture
import Extensions
import OnlyAgent
import SwiftUI

@available(macOS 26.0, *)
public struct AphroditeEditorView: View {
    let store: StoreOf<AphroditeReducer>
    let app: AphroditeApp

    public init(store: StoreOf<AphroditeReducer>, app: AphroditeApp) {
        self.store = store
        self.app = app
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.vertical, 10)
            Divider()
            splitContent
        }
    }

    private var header: some View {
        HStack {
            Button("Back".localized(), systemImage: "chevron.left") { store.send(.closeEditorTapped) }
            Text(app.title).font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private var splitContent: some View {
        #if os(macOS)
        HSplitView {
            conversationPane
                .frame(minWidth: 260, idealWidth: 330)
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        HStack(spacing: 0) {
            conversationPane.frame(minWidth: 260, idealWidth: 330)
            Divider()
            previewPane.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    private var conversationPane: some View {
        Form {
            Section("Conversation".localized()) {
                ForEach(app.conversation) { turn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.prompt)
                        Label("App updated".localized(), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if app.conversation.isEmpty { Text("Result available".localized()).foregroundStyle(.secondary) }
            }
            Section {
                Picker("Provider".localized(), selection: Binding(get: { store.selection?.provider ?? .openai }, set: { store.send(.providerSelected($0)) })) {
                    ForEach(ModelProvider.allCases, id: \.self) { Text($0.aphroditeDisplayName).tag($0) }
                }
                Picker("Model".localized(), selection: Binding(get: { store.selection?.model ?? "" }, set: { store.send(.modelSelected($0)) })) {
                    ForEach(store.models[store.selection?.provider ?? .openai] ?? [], id: \.self) { Text($0).tag($0) }
                }
                let selectedProvider = store.selection?.provider ?? .openai
                if store.modelLoadErrors[selectedProvider] != nil {
                    HStack {
                        Text("Models could not be loaded for this provider.".localized()).foregroundStyle(.red)
                        Button("Retry".localized()) { store.send(.loadModels(selectedProvider)) }
                    }
                }
                TextEditor(text: Binding(get: { store.editPrompt }, set: { store.send(.editPromptChanged($0)) }))
                    .frame(minHeight: 80)
                    .accessibilityLabel("Describe a change".localized())
                    .disabled(store.isEditing)
                HStack {
                    if store.isEditing {
                        ProgressView()
                        Button("Cancel".localized()) { store.send(.cancelEditTapped) }
                    } else {
                        Button("Send".localized()) { store.send(.sendEditTapped) }
                            .disabled(store.editPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGenerating || store.storageState != .ready || !hasValidSelection)
                    }
                }
                if let error = store.error {
                    HStack {
                        Text(error.rawValue.localized()).foregroundStyle(.red)
                        if error == .storageLoadFailed { Button("Retry".localized()) { store.send(.reloadLibrary) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var previewPane: some View {
        Group {
            #if os(macOS)
            AphroditeFittedPreview(html: app.html)
                .id(app.id)
            #else
            Color.clear
            #endif
        }
        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hasValidSelection: Bool {
        guard let selection = store.selection else { return false }
        return store.models[selection.provider]?.contains(selection.model) == true
    }
}
