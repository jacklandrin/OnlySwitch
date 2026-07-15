import ComposableArchitecture
import Extensions
import SwiftUI

struct RemoteAccessSettingsView: View {
    @Bindable var store: StoreOf<RemoteAccessSettingsFeature>

    var body: some View {
        Form {
            Section("Remote Access".localized()) {
                Toggle(
                    "Enable Remote Access".localized(),
                    isOn: $store.isEnabled.sending(\.setEnabled)
                )
                TextField(
                    "Display Name".localized(),
                    text: $store.displayName.sending(\.displayNameChanged)
                )

                LabeledContent("Status".localized(), value: statusDescription)
                LabeledContent("Connected Devices".localized(), value: store.connectionCount.formatted())
            }

            Section("Pairing".localized()) {
                if let code = store.pairingCode {
                    LabeledContent("Pairing Code".localized()) {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                            .bold()
                            .textSelection(.disabled)
                            .accessibilityLabel(
                                "Pairing Code %@".localizeWithFormat(
                                    arguments: code.map(String.init).joined(separator: " ")
                                )
                            )
                    }
                    LabeledContent(
                        "Expires In".localized(),
                        value: Duration.seconds(store.pairingSecondsRemaining).formatted(.time(pattern: .minuteSecond))
                    )
                    Button("Cancel Pairing".localized(), role: .cancel) {
                        store.send(.cancelPairingTapped)
                    }
                } else {
                    Button("Start Pairing".localized()) {
                        store.send(.startPairingTapped)
                    }
                    .disabled(!store.isEnabled || !isListening || store.isPairingRequestInFlight)
                }
            }

            Section("Paired Devices".localized()) {
                if store.pairedDevices.isEmpty {
                    ContentUnavailableView(
                        "No Paired Devices".localized(),
                        systemImage: "iphone.slash",
                        description: Text("Start pairing to connect an iPhone or iPad.".localized())
                    )
                } else {
                    ForEach(store.pairedDevices) { device in
                        LabeledContent {
                            Button("Revoke".localized(), role: .destructive) {
                                store.send(.revokeTapped(device.id))
                            }
                            .disabled(store.revokingDeviceIDs.contains(device.id))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                if let date = device.lastConnectedAt {
                                    Text("Last connected %@".localizeWithFormat(
                                        arguments: date.formatted(date: .abbreviated, time: .shortened)
                                    ))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not connected yet".localized())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await store.send(.task).finish() }
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private var isListening: Bool {
        if case .listening = store.hostStatus { return true }
        return false
    }

    private var statusDescription: String {
        switch store.hostStatus {
        case .stopped: "Stopped".localized()
        case .starting: "Starting…".localized()
        case let .listening(port): "Listening on port %d".localizeWithFormat(arguments: Int(port))
        case let .failed(message): "Failed: %@".localizeWithFormat(arguments: message)
        }
    }
}
