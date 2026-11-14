import ComposableArchitecture
import Extensions
import SwiftUI

/// The Desktop Pet settings page: chooses what clicking the pet does.
struct DesktopPetSettingsView: View {
    @Bindable var store: StoreOf<DesktopPetSettingsFeature>

    var body: some View {
        Form {
            Section {
                Picker("Desktop Pet Click Action".localized(), selection: $store.mode) {
                    Text("Desktop Pet Show OnlyControl".localized())
                        .tag(DesktopPetSettingsFeature.Mode.onlyControl)
                    Text("Desktop Pet Run Control".localized())
                        .tag(DesktopPetSettingsFeature.Mode.control)
                }
                .pickerStyle(.radioGroup)

                if store.mode == .control {
                    LabeledContent("Desktop Pet Control".localized()) {
                        DesktopPetControlPicker(store: store)
                    }

                    if store.isTargetMissing {
                        Label("Desktop Pet Control Missing".localized(), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            } footer: {
                Text("Desktop Pet Click Action Footer".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: store.mode)
        .task { await store.send(.task).finish() }
    }
}
