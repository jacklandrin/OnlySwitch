import ComposableArchitecture
import DesktopPet
import DesktopPetSkinKit
import Extensions
import SwiftUI

/// Describe a pet, generate it with the selected model, preview every state, then save it.
struct DesktopPetSkinGeneratorSheet: View {
    @Bindable var store: Store<DesktopPetSkinsFeature.Generator, DesktopPetSkinsFeature.GeneratorAction>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A vertical text field draws its own placeholder, so it always lines up with the caret.
            TextField(placeholder, text: $store.description, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(4, reservesSpace: true)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .disabled(store.isGenerating)

            if !store.isModelSelected {
                Label("Desktop Pet No Model".localized(), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Button(generateTitle) { store.send(.generateTapped) }
                    .disabled(!canGenerate)
                if store.isGenerating {
                    ProgressView().controlSize(.small)
                    Text("Desktop Pet Generating".localized())
                        .foregroundStyle(.secondary)
                }
            }

            if let draft = store.draft {
                preview(of: draft)
            }

            if let message = store.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel".localized(), role: .cancel) { store.send(.cancelTapped) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if store.draft != nil {
                    Button("Desktop Pet Save Skin".localized()) { store.send(.saveTapped) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(store.isGenerating)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private var isRefining: Bool { store.draft != nil }

    private var placeholder: String {
        (isRefining ? "Desktop Pet Describe Change" : "Desktop Pet Describe").localized()
    }

    private var generateTitle: String {
        (isRefining ? "Desktop Pet Apply Change" : "Desktop Pet Generate").localized()
    }

    private var canGenerate: Bool {
        store.isModelSelected && !store.isGenerating
            && !store.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func preview(of draft: DesktopPetSkinDraft) -> some View {
        VStack(spacing: 10) {
            DesktopPetSkinWebView(
                skin: DesktopPetSkin(
                    id: Self.previewID, name: draft.name, summary: "", createdAt: .distantPast,
                    contractVersion: DesktopPetSkinContract.version, markup: draft.markup
                ),
                state: .preview(store.previewAnimation),
                reduceMotion: false,
                isPaused: false
            )
            .frame(width: CGFloat(DesktopPetSkinContract.canvasWidth), height: CGFloat(DesktopPetSkinContract.canvasHeight))
            .padding(16)
            .modifier(DesktopPetSkinPreviewBackground())
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                animationPicker.pickerStyle(.segmented)
                animationPicker.pickerStyle(.menu)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var animationPicker: some View {
        Picker("Desktop Pet Appearance".localized(), selection: $store.previewAnimation) {
            ForEach(DesktopPetAnimation.allCases, id: \.self) { animation in
                Text("Desktop Pet State \(animation.rawValue)".localized()).tag(animation)
            }
        }
        .labelsHidden()
    }

    private static let previewID = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
}

private struct DesktopPetSkinPreviewBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
