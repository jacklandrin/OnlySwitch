//
//  CustomizeView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import SwiftUI
import AlertToast
import KeyboardShortcuts
import Switches
import Utilities

struct CustomizeView: View {
    @ObservedObject var customizeVM = CustomizeVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    @State private var searchText = ""

    var body: some View {
        let currentLanguage = langManager.currentLang
        let sections = customizeVM.sections(
            matching: searchText,
            currentLanguage: currentLanguage
        )

        VStack(alignment: .leading) {
            Text("To add or remove any switches on list".localized())
                .padding(10)
            TextField(
                "Search Built-In Switches".localized(),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(Text("Search Built-In Switches".localized()))
            .environment(\.locale, Locale(identifier: currentLanguage))
            .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if sections.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .accessibilityHidden(true)
                            Text("No Built-In Switches Found".localized())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("No Built-In Switches Found".localized()))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(sections, id: \.section.id) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.section.titleKey.localized())
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.horizontal)

                                ForEach(section.items, id: \.type) { item in
                                    CustomizeRowView(
                                        item: item,
                                        currentLang: currentLanguage
                                    )
                                }
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            Divider()
                .padding(.bottom, 10)
        }
        .toast(isPresenting: $customizeVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: customizeVM.errorInfo.localized())
        }
    }
}

private struct CustomizeRowView: View {
    @ObservedObject var item: CustomizeItem
    @ObservedObject private var preferencesvm = PreferencesObserver.shared
    let currentLang: String

    var body: some View {
        let localizedTitle = item.barInfo.title.localized()

        HStack {
            Toggle(localizedTitle, isOn: $item.toggle)
                .labelsHidden()
                .accessibilityLabel(Text(localizedTitle))
            if let iconImage = item.iconImage {
                Image(nsImage: iconImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .accessibilityHidden(true)
            }
            Text(localizedTitle)
                .frame(width: 170, alignment: .leading)
                .padding(.trailing, 10)
                .accessibilityHidden(true)
            KeyboardShortcuts.Recorder(for: item.keyboardShortcutName)
                .environment(\.locale, Locale(identifier: currentLang))
                .accessibilityLabel(Text("\(localizedTitle), \("Shortcuts".localized())"))
            extraSettingsButton
                .padding(.leading, 10)

            Spacer()
        }
        .padding(.leading)
    }

    @ViewBuilder
    private var extraSettingsButton: some View {
        if item.type == .hideMenubarIcons {
            Button {
                preferencesvm.preferences.menubarCollaspable.toggle()
            } label: {
                Text(extraSettingsActionTitle)
            }
            .accessibilityLabel(Text(extraSettingsAccessibilityLabel))
        } else if item.type == .radioStation || item.type == .backNoises {
            Button {
                preferencesvm.preferences.radioEnable.toggle()
                if preferencesvm.preferences.radioEnable {
                    PlayerManager.shared.player.setupRemoteCommandCenter()
                } else {
                    RadioStationSwitch.shared.playerItem.isPlaying = false
                    PlayerManager.shared.player.clearCommandCenter()
                }
            } label: {
                Text(extraSettingsActionTitle)
            }
            .accessibilityLabel(Text(extraSettingsAccessibilityLabel))
        }
    }

    private var extraSettingsActionTitle: String {
        let isEnabled = item.type == .hideMenubarIcons
            ? preferencesvm.preferences.menubarCollaspable
            : preferencesvm.preferences.radioEnable
        return (isEnabled ? "Disable" : "Enable").localized()
    }

    private var extraSettingsAccessibilityLabel: String {
        "\(extraSettingsActionTitle) \(item.barInfo.title.localized())"
    }
}

#if DEBUG
struct CustomizeView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeView()
    }
}
#endif
