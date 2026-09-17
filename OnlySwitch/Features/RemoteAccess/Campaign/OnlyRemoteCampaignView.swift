import ComposableArchitecture
import Extensions
import SwiftUI

struct OnlyRemoteCampaignView: View {
    let store: StoreOf<OnlyRemoteCampaignFeature>
    let closeWindow: () -> Void

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 20) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(.largeTitle))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("OnlyRemote is here".localized())
                        .font(.title)
                        .bold()

                    Text("Control OnlySwitch from your iPhone or iPad".localized())
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Text(
                        "Use OnlyRemote on the same local network to run switches and control your Mac from anywhere in the room."
                            .localized()
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        store.send(.downloadTapped)
                        closeWindow()
                    } label: {
                        Label("Download on the App Store".localized(), systemImage: "apple.logo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint(
                        Text("Opens the OnlyRemote App Store page.".localized())
                    )

                    Button {
                        store.send(.openRemoteAccessSettingsTapped)
                        closeWindow()
                    } label: {
                        Label("Set Up Remote Access".localized(), systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint(
                        Text("Opens iOS Remote settings in OnlySwitch.".localized())
                    )

                    Button("Not Now".localized()) {
                        store.send(.dismissTapped)
                        closeWindow()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        Text("Closes this announcement.".localized())
                    )
                }
            }
            .padding(32)
            .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)
            .accessibilityElement(children: .contain)
        }
    }
}
