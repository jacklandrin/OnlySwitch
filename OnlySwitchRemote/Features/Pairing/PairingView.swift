import ComposableArchitecture
import SwiftUI

struct PairingView: View {
    @Bindable var store: StoreOf<PairingFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("Discovered Macs") {
                    if store.discoveredMacs.isEmpty {
                        if store.isDiscovering {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Looking for Macs on your local network…")
                            }
                            .accessibilityElement(children: .combine)
                        } else {
                            ContentUnavailableView(
                                "No Macs Found",
                                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                                description: Text("Make sure remote access and pairing are active in OnlySwitch on your Mac.")
                            )
                            Button("Retry Discovery", systemImage: "arrow.clockwise") {
                                store.send(.retryDiscoveryTapped)
                            }
                        }
                    } else {
                        ForEach(store.discoveredMacs) { mac in
                            Button {
                                store.send(.selectMac(mac.id))
                            } label: {
                                HStack {
                                    Label(mac.displayName, systemImage: "desktopcomputer")
                                    Spacer()
                                    if store.selectedMacID == mac.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(mac.displayName), \(store.selectedMacID == mac.id ? "selected" : "not selected")")
                            .accessibilityHint("Selects this Mac for pairing")
                        }
                    }
                }

                Section("Pairing Code") {
                    TextField("12-character code", text: $store.code.sending(\.codeChanged))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .privacySensitive()
                        .accessibilityLabel("Pairing code")
                        .accessibilityValue("\(store.code.count) of 12 characters entered")

                    Text(store.helpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let issue = store.issue {
                    Section("Pairing Problem") {
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(issue.helpText)
                            .font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button {
                        store.send(.pairTapped)
                    } label: {
                        HStack {
                            Spacer()
                            if store.isPairing {
                                ProgressView()
                                    .accessibilityLabel("Pairing in progress")
                            } else {
                                Text("Pair Mac")
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.canPair == false)
                }
            }
            .navigationTitle("Pair a Mac")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelTapped) }
                }
            }
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.onDisappear) }
    }
}
