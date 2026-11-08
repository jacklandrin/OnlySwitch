import ComposableArchitecture
import SwiftUI

struct RemoteTabSettingsView: View {
    let store: StoreOf<GlobalSettingsFeature>

    var body: some View {
        List {
            Section {
                ForEach(RemoteAppPage.allCases, id: \.self) { page in
                    Toggle(isOn: Binding(
                        get: { store.tabConfiguration.isVisible(page) },
                        set: { store.send(.tabVisibilityChanged(page, $0)) }
                    )) {
                        HStack(spacing: 8) {
                            Label {
                                Text(page.title)
                            } icon: {
                                RemoteAppPageIcon(page: page)
                                    .foregroundStyle(Color.accentColor)
                            }
                            if page.requiresPlus {
                                Text("Plus")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Requires OnlyRemote Plus")
                            }
                        }
                    }
                    .disabled(page.isAlwaysVisible)
                }
            } header: {
                Text("Visible Tabs")
            } footer: {
                Text("Choose which tabs appear at the bottom of the screen. Controls is always shown.")
            }
        }
        .navigationTitle("Tabs")
        .toolbarTitleDisplayMode(.inline)
    }
}
