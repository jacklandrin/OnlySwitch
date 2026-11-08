import ComposableArchitecture
import SwiftUI

struct PairingView: View {
    @Bindable var store: StoreOf<PairingFeature>

    var body: some View {
        NavigationStack {
            List {
                Section("Discovered Macs") {
                    if store.discoveredMacs.isEmpty {
                        switch store.discoveryPhase {
                        case .idle, .searching:
                            HStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.accentColor)
                                    .accessibilityHidden(true)
                                Text("Searching your local network…")
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Searching your local network…")

                        case .empty, .found:
                            ContentUnavailableView(
                                "No Macs Found",
                                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                                description: Text("Make sure remote access and pairing are active in OnlySwitch on your Mac.")
                            )
                            .accessibilityElement(children: .combine)
                            Button("Retry", systemImage: "arrow.clockwise") {
                                store.send(.retryDiscoveryTapped)
                            }
                            .accessibilityLabel("Retry Mac discovery")
                            .accessibilityHint("Searches your local network for OnlySwitch Macs again")

                        case .needsLocalNetworkAccess:
                            ContentUnavailableView(
                                "Allow Local Network Access",
                                systemImage: "network.badge.shield.half.filled",
                                description: Text("Allow OnlyRemote to find devices in Settings, then return and retry.")
                            )
                            .accessibilityElement(children: .combine)
                            Button("Open Settings", systemImage: "gear") {
                                store.send(.openAppSettingsTapped)
                            }
                            .accessibilityLabel("Open Settings")
                            .accessibilityHint("Opens OnlyRemote settings so you can allow local network access")
                            Button("Retry", systemImage: "arrow.clockwise") {
                                store.send(.retryDiscoveryTapped)
                            }
                            .accessibilityLabel("Retry Mac discovery")
                            .accessibilityHint("Searches your local network for OnlySwitch Macs again")

                        case .temporarilyUnavailable:
                            ContentUnavailableView(
                                "Mac Discovery Is Temporarily Unavailable",
                                systemImage: "wifi.exclamationmark",
                                description: Text("Check your network connection, then retry.")
                            )
                            .accessibilityElement(children: .combine)
                            Button("Retry", systemImage: "arrow.clockwise") {
                                store.send(.retryDiscoveryTapped)
                            }
                            .accessibilityLabel("Retry Mac discovery")
                            .accessibilityHint("Searches your local network for OnlySwitch Macs again")
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
                            .disabled(store.isPairing)
                            .accessibilityLabel(
                                store.selectedMacID == mac.id
                                    ? Text("Selected Mac: \(mac.displayName)")
                                    : Text("Unselected Mac: \(mac.displayName)")
                            )
                            .accessibilityHint("Selects this Mac for pairing")
                        }
                    }
                }

                Section("Pairing Code") {
                    TextField("12-character code", text: $store.code.sending(\.codeChanged))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(store.isPairing)
                        .textContentType(.oneTimeCode)
                        .privacySensitive()
                        .accessibilityLabel("Pairing code")
                        .accessibilityValue("\(store.code.count) of 12 characters entered")

                    Text(store.helpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(store.helpText))
                }

                if let issue = store.issue {
                    Section("Pairing Problem") {
                        Label {
                            Text(issue.message)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                            .foregroundStyle(.red)
                        Text(issue.helpText)
                            .font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button {
                        store.send(store.isFinalizing ? .retryFinalizeTapped : .pairTapped)
                    } label: {
                        HStack {
                            Spacer()
                            if store.isFinalizing, store.issue != nil {
                                Text("Retry Finalization")
                            } else if store.isPairing {
                                ProgressView()
                                    .accessibilityLabel("Pairing in progress")
                            } else {
                                Text("Pair Mac")
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.isFinalizing ? store.issue == nil : store.canPair == false)
                }
            }
            .navigationTitle("Pair a Mac")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if store.isFinalizing == false {
                        Button("Cancel") { store.send(.cancelTapped) }
                    }
                }
            }
        }
        .interactiveDismissDisabled(store.isDismissDisabled)
        .task { await store.send(.task).finish() }
    }
}
