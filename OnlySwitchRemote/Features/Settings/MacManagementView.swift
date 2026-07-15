import ComposableArchitecture
import SwiftUI

struct MacManagementView: View {
    @Bindable var store: StoreOf<MacManagementFeature>

    var body: some View {
        Form {
            Section("Mac") {
                LabeledContent("Name", value: store.mac.displayName)
                LabeledContent("Status") { Text(store.connectionStatus.title) }
                if let endpoint = store.mac.lastEndpointDescription {
                    LabeledContent("Last address", value: endpoint)
                }
                if let date = store.mac.lastConnectedAt {
                    LabeledContent("Last connected") {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            }

            if store.mac.requiresPairing || store.connectionStatus == .needsPairing {
                Section {
                    Button("Pair Again", systemImage: "link.badge.plus") {
                        store.send(.rePairTapped)
                    }
                } footer: {
                    Text("This Mac no longer accepts the saved credential. Start pairing in OnlySwitch on the Mac first.")
                }
            }

            if let issue = store.issue {
                Section {
                    Text(issue.message)
                        .foregroundStyle(.red)
                    Button("Retry Forgetting") { store.send(.retryForgetTapped) }
                        .disabled(store.isForgetting)
                }
            }

            Section {
                Button("Forget This Mac", systemImage: "trash", role: .destructive) {
                    store.send(.forgetTapped)
                }
                .disabled(store.isForgetting)
            } footer: {
                Text("Forgetting removes this Mac’s credential, cached controls, statuses, and dashboard layout from this device.")
            }
        }
        .navigationTitle(store.mac.displayName)
        .confirmationDialog(
            "Forget \(store.mac.displayName)?",
            isPresented: Binding(
                get: { store.isForgetConfirmationPresented },
                set: { if $0 == false { store.send(.forgetConfirmationDismissed) } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forget Mac", role: .destructive) { store.send(.confirmForgetTapped) }
            Button("Cancel", role: .cancel) { store.send(.forgetConfirmationDismissed) }
        } message: {
            Text("You’ll need a new pairing code to add this Mac again.")
        }
        .overlay {
            if store.isForgetting {
                ProgressView("Forgetting Mac…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }
}
