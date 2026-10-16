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
        .background(.background)
    }

    private var header: some View {
        HStack {
            Button("Back".localized(), systemImage: "chevron.left") { store.send(.closeEditorTapped) }
            Text(app.title).font(.headline)
            Spacer()
            ShareLink(
                item: AphroditeSharePayload(app: app),
                preview: SharePreview(app.title, image: sharePreviewImage)
            ) {
                Label("Share mini app".localized(), systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share mini app".localized())
            .accessibilityValue(app.title)
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
                    .aphroditeTextEditorInset()
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
        VStack(alignment: .leading, spacing: 8) {
            AphroditeSectionHeader("Preview".localized(), systemImage: "macwindow")
                .padding(.horizontal)
                .padding(.top, 10)
            Group {
            #if os(macOS)
            AphroditeFittedPreview(app: app)
                .id(app.id)
            #else
            Color.clear
            #endif
            }
        }
        .frame(minWidth: AphroditeVisualStyle.minimumPreviewWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(8)
        .aphroditePanelSurface()
    }

    private var hasValidSelection: Bool {
        guard let selection = store.selection else { return false }
        return store.models[selection.provider]?.contains(selection.model) == true
    }

    private var sharePreviewImage: Image {
        #if os(macOS)
        if let image = AphroditeIconRenderer.image(svg: app.iconSVG) { return Image(nsImage: image) }
        #endif
        return Image(systemName: "sparkles.rectangle.stack")
    }
}
