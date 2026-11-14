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
            DesktopPetSkinRow(
                skin: nil,
                isSelected: store.selectedID == nil,
                onSelect: { store.send(.selected(nil)) },
                onEdit: {},
                onDelete: {}
            )

            ForEach(store.skins) { skin in
                DesktopPetSkinRow(
                    skin: skin,
                    isSelected: store.selectedID == skin.id,
                    onSelect: { store.send(.selected(skin.id)) },
                    onEdit: { store.send(.editTapped(skin.id)) },
                    onDelete: { skinPendingDeletion = skin }
                )
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
