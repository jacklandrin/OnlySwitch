import ComposableArchitecture
import SwiftUI

/// The sheet for adding or editing a station by hand.
public struct RadioStationEditorView: View {
    @Bindable var store: StoreOf<RadioStationEditorFeature>
    @FocusState private var focusedField: Field?

    private enum Field { case name, url }

    public init(store: StoreOf<RadioStationEditorFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RadioStationArtwork(name: store.name, url: nil, size: 40)
                Text(RadioStrings.text(store.editingID == nil ? "Radio Add Station" : "Radio Edit Station"))
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(RadioStrings.text("Radio Station Name"))
                    .font(.callout.weight(.medium))
                TextField(RadioStrings.text("Radio Station Name Placeholder"), text: $store.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .url }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(RadioStrings.text("Radio Stream URL"))
                    .font(.callout.weight(.medium))
                TextField(RadioStrings.text("Radio Stream URL Placeholder"), text: $store.streamURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($focusedField, equals: .url)
                    .onSubmit { store.send(.saveTapped) }
                Group {
                    if let issue = store.visibleIssue {
                        Label(issue.text, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Text(RadioStrings.text("Radio Stream URL Hint"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: 0.15), value: store.visibleIssue)
            }

            HStack {
                Spacer()
                Button(RadioStrings.text("Radio Cancel"), role: .cancel) { store.send(.cancelTapped) }
                    .keyboardShortcut(.cancelAction)
                Button(RadioStrings.text("Radio Save")) { store.send(.saveTapped) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focusedField = .name }
    }
}
