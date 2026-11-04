#if os(macOS)
import Extensions
import SwiftUI

/// Shows a display's brightness percent; clicking it lets the user type an exact value.
struct BrightnessPercentField: View {
    let level: Double
    let isEnabled: Bool
    let displayName: String
    let submit: (String) -> Void

    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            HStack(spacing: 2) {
                TextField(displayName + ", " + "Brightness".localized(), text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand { isEditing = false }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
                Text(verbatim: "%").foregroundStyle(.secondary)
            }
            .font(.body.monospacedDigit())
            .onAppear { isFocused = true }
        } else {
            Button {
                text = BrightnessPercentInput.text(for: level)
                isEditing = true
            } label: {
                Text(level, format: .percent.precision(.fractionLength(0)))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .help(isEnabled ? "Click to enter a brightness percentage".localized() : "")
            .accessibilityHint(isEnabled ? "Click to enter a brightness percentage".localized() : "")
            .accessibilityLabel(displayName + ", " + "Brightness".localized())
            .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
        }
    }

    /// Escape ends editing first, so the focus loss that follows does not submit.
    private func commit() {
        guard isEditing else { return }
        isEditing = false
        submit(text)
    }
}
#endif
