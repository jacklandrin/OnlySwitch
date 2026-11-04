import SwiftUI

/// A rounded search field with a clear button.
struct ScheduleSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(ScheduleStrings.text("Cancel"), systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .scheduleSurface(.capsule)
    }

    private func clear() {
        text = ""
    }
}
