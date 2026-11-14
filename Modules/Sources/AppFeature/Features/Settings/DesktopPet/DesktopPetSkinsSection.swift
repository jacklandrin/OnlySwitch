import ComposableArchitecture
import DesktopPetSkinKit
import Extensions
import SwiftUI

/// Chooses between the built-in pet and saved AI-generated pets, and opens the generator.
struct DesktopPetSkinsSection: View {
    @Bindable var store: StoreOf<DesktopPetSkinsFeature>
    @State private var skinPendingDeletion: DesktopPetSkin?

    var body: some View {
        Section {
            Picker(
                "Desktop Pet Appearance".localized(),
                selection: Binding(
                    get: { store.selectedID },
                    set: { store.send(.selected($0)) }
                )
            ) {
                Text("Desktop Pet Built-in".localized()).tag(UUID?.none)
                ForEach(store.skins) { skin in
                    Text(skin.name).tag(UUID?.some(skin.id))
                }
            }
            .pickerStyle(.radioGroup)

            ForEach(store.skins) { skin in
                LabeledContent(skin.name) {
                    Button("Desktop Pet Delete Skin".localized(), systemImage: "trash", role: .destructive) {
                        skinPendingDeletion = skin
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Desktop Pet Delete Skin".localized())
                }
            }

            Button("Desktop Pet Create With AI".localized(), systemImage: "sparkles") {
                store.send(.createTapped)
            }
        } header: {
            Text("Desktop Pet Appearance".localized())
        } footer: {
            Text("Desktop Pet Appearance Footer".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            "Desktop Pet Delete Skin".localized(),
            isPresented: Binding(
                get: { skinPendingDeletion != nil },
                set: { if !$0 { skinPendingDeletion = nil } }
            ),
            presenting: skinPendingDeletion
        ) { skin in
            Button("Desktop Pet Delete Skin".localized(), role: .destructive) {
                store.send(.deleteTapped(skin.id))
            }
        } message: { skin in
            Text(skin.name)
        }
        .sheet(isPresented: Binding(
            get: { store.generator != nil },
            set: { if !$0 { store.send(.generator(.cancelTapped)) } }
        )) {
            if let generatorStore = store.scope(state: \.generator, action: \.generator) {
                DesktopPetSkinGeneratorSheet(store: generatorStore)
            }
        }
    }
}
