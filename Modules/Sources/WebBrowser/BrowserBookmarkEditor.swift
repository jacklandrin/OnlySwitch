import ComposableArchitecture
import SwiftUI

/// Add/edit sheet for a bookmark; validation happens in `BrowserFeature`.
struct BrowserBookmarkEditor: View {
    let store: StoreOf<BrowserFeature>
    let draft: BrowserBookmarkDraft

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(BrowserStrings.text("Browser Bookmark Title"), text: Binding(
                    get: { draft.title },
                    set: { store.send(.draftTitleChanged($0)) }
                ), prompt: Text(BrowserStrings.text("Browser Bookmark Title Placeholder")))

                TextField(BrowserStrings.text("Browser Bookmark Address"), text: Binding(
                    get: { draft.address },
                    set: { store.send(.draftAddressChanged($0)) }
                ), prompt: Text(verbatim: "https://example.com"))
                .autocorrectionDisabled()
                .onSubmit { store.send(.draftSaveTapped) }

                if draft.showsInvalidAddress {
                    Text(BrowserStrings.text("Browser Invalid Address"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle(BrowserStrings.text("Browser Mobile Version"), isOn: Binding(
                    get: { draft.usesMobileUserAgent },
                    set: { store.send(.draftMobileUserAgentChanged($0)) }
                ))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(BrowserStrings.text("Browser Cancel"), role: .cancel) { store.send(.draftCancelTapped) }
                    .keyboardShortcut(.cancelAction)
                Button(BrowserStrings.text("Browser Save")) { store.send(.draftSaveTapped) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420)
        .navigationTitle(BrowserStrings.text(draft.editingID == nil ? "Browser Add Bookmark" : "Browser Edit Bookmark"))
    }
}
