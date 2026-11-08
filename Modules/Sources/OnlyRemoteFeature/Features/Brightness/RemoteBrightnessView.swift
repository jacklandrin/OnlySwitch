import ComposableArchitecture
import RemoteCore
import SwiftUI

struct RemoteBrightnessView: View {
    let store: StoreOf<RemoteBrightnessFeature>

    var body: some View {
        Group {
            if store.selectedMacID == nil {
                ContentUnavailableView(
                    "No Mac Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a paired Mac from the navigation bar.")
                )
            } else if store.connectionState != .authenticated {
                ContentUnavailableView(
                    "Brightness",
                    systemImage: "wifi.slash",
                    description: Text("The selected Mac is offline.")
                )
            } else if let message = store.availabilityMessage {
                ContentUnavailableView(
                    "Brightness",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: message)
                )
            } else if let snapshot = store.snapshot {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let commandError = store.commandError {
                            warning(Text(verbatim: commandError))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if snapshot.displays.isEmpty {
                            RemoteSystemMonitorCardSurface {
                                Label("No displays found", systemImage: "display")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(snapshot.displays) { display in
                            displayCard(display)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, RemotePageTabBar.contentBottomInset + 16)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Brightness")
    }

    private func displayCard(_ display: RemoteBrightnessDisplay) -> some View {
        let isControllable = display.control != .unavailable
        return RemoteSystemMonitorCardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: display.control == .native ? "laptopcomputer" : "display")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: display.name)
                            .font(.headline)
                        Text(controlCaption(display.control))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                RemoteMixerSlider(
                    label: String(localized: "Brightness"),
                    value: (store.state.level(for: display.id) ?? display.level) * 100,
                    isEnabled: store.canSendCommands && isControllable,
                    minimumSymbol: "sun.min",
                    maximumSymbol: "sun.max",
                    onChange: { store.send(.levelChanged(displayID: display.id, level: $0 / 100)) },
                    onEditingChanged: { if $0 == false { store.send(.levelCommitted(displayID: display.id)) } }
                )
                if display.hasError {
                    warning(Text("The Mac could not update brightness."))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: display.name))
    }

    private func warning(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.orange)
    }

    private func controlCaption(_ control: RemoteBrightnessDisplay.Control) -> LocalizedStringKey {
        switch control {
        case .native, .ddc: "Hardware brightness"
        case .software: "Software dimming"
        case .unavailable: "Brightness unavailable"
        }
    }
}
