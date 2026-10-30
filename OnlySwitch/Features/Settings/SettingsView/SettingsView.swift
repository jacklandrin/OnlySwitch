//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import Aphrodite
import Authenticator
import Utilities
import OnlyAgent
import XcodeCleaner
import AppUninstaller
import ComposableArchitecture
import Screenshots
import Tailscale
import Extensions
import KeyboardShortcuts

struct SettingsView: View {
    @StateObject var settingVM = SettingsVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    @Environment(\.colorScheme) private var colorScheme

    init(settingItem: Binding<SettingsItem?> = .constant(nil)) {
        if let item = settingItem.wrappedValue {
            settingVM.selection = item
        }
    }

    func naviagtionView(currentLang: String) -> some View {
        NavigationView {
            List(selection: $settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        page(item: item)
                            .navigationTitle(item.titleLocalizationKey.localized())
                    } label:{
                        Text(item.titleLocalizationKey.localized())
                            .id(currentLang)
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Settings".localized())
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        settingVM.toggleSliderbar()
                    }, label: {
                        Image(systemName: "sidebar.leading")
                    })
                }
            }
    }

    @available(macOS 13.3, *)
    func naviagtionSplitView(currentLang: String) -> some View {
        NavigationSplitView(sidebar: {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink(value: item) {
                        Text(item.titleLocalizationKey.localized())
                            .id(currentLang)
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.sidebar)
        }, detail: {
            let selection = settingVM.selection ?? .General
            page(item: selection)
                .navigationTitle(selection.titleLocalizationKey.localized())
        })
    }

    @ViewBuilder
    func page(item: SettingsItem) -> some View {
        switch item {
            case .AirPods:
                AirPodsSettingView()

            case .Radio:
                RadioSettingView(store: settingVM.radioStationsStore)
                    .id(langManager.currentLang)

            case .Authenticator:
                AuthenticatorSettingsView()

            case .XcodeCleaner:
                ScrollView {
                    XcodeCleanerView(store: settingVM.xcodeCleanerStore, managesScrolling: false)
                        .id(langManager.currentLang)
                }
                .background(.background)

            case .AppUninstaller:
                ScrollView {
                    AppUninstallerView(store: settingVM.appUninstallerStore, managesScrolling: false)
                        .id(langManager.currentLang)
                }
                .background(.background)

            case .Screenshots:
                ScrollView {
                    VStack(spacing: 0) {
                        ScreenshotsSettingsControls(store: settingVM.screenshotsStore, folderPath: settingVM.screenshotsFolderURL.path)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .frame(maxWidth: 900)
                            .frame(maxWidth: .infinity)
                            .tint(colorScheme == .dark ? .mint : .accentColor)
                        ScreenshotsView(store: settingVM.screenshotsStore, resolvesFlightTarget: false)
                            .id(langManager.currentLang)
                    }
                }
                .background(.background)

            case .Tailscale:
                TailscaleSettingsView(store: settingVM.tailscaleStore)
                    .id(langManager.currentLang)
                    .onReceive(NotificationCenter.default.publisher(for: .changeSettings)) { _ in
                        settingVM.tailscaleStore.send(.refresh)
                    }
                    .onChange(of: settingVM.tailscaleStore.snapshot?.connection) { _, _ in
                        NotificationCenter.default.post(name: .changeSettings, object: nil)
                    }

            case .SystemMonitor:
                SystemMonitorSettingsView()

            case .PomodoroTimer:
                PomodoroTimerSettingView()

            case .Shortcuts:
                ShortcutsView()

            case .General:
                GeneralView()

            case .Customize:
                CustomizeView()

            case .Tabs:
                TabVisibilitySettingsView()

            case .HideMenubarIcons:
                HideMenubarIconsSettingView()

            case .BackNoises:
                BackNoisesSettingView()

            case .KeepAwake:
                KeepAwakeSettingView()

            case .DimScreen:
                DimScreenSettingView()

            case .Evolution:
                EvolutionView(store: settingVM.evolutionStore)

            case .ModelProviders:
                if #available(macOS 26.0, *) {
                    ModelProviderSettingView()
                } else {
                    EmptyView()
                }

            case .Aphrodite:
                if #available(macOS 26.0, *) {
                    AphroditeSettingsView(store: settingVM.aphroditeStore)
                } else {
                    AphroditeUnavailableView()
                }
            
            case .NightShift:
                NightShiftSettingsView()

            case .KeyLight:
                KeyLightView(store: settingVM.keyLightStore)

            case .PrivilegedAccess:
                PrivilegedAccessView()

            case .iOSRemote:
                RemoteAccessSettingsView(store: settingVM.remoteAccessStore)

            case .About:
                AboutView()
        }
    }

    var body: some View {
        if #available(macOS 13.3, *) {
            naviagtionSplitView(currentLang: langManager.currentLang)
        } else {
            naviagtionView(currentLang: langManager.currentLang)
        }
    }

}

/// The tab shortcut (disabled while the tab is hidden on the Tabs page), the opt-in system screenshot takeover
/// and the collection folder. Toggling collection is a `ScreenshotsFeature` action; the view only reflects `captureStatus`.
private struct ScreenshotsSettingsControls: View {
    let store: StoreOf<ScreenshotsFeature>
    let folderPath: String
    @AppStorage(UserDefaults.Key.showScreenshotsTab) private var showScreenshotsTab = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open Screenshots Tab".localized())
                Spacer(minLength: 12)
                KeyboardShortcuts.Recorder(for: .openScreenshotsTab)
                    .accessibilityLabel(Text("Open Screenshots Tab".localized()))
            }
            .padding(12)
            .disabled(!showScreenshotsTab)
            Divider().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Collect System Screenshots".localized())
                    Spacer(minLength: 12)
                    Toggle("Collect System Screenshots".localized(), isOn: Binding(get: { store.captureStatus != .disabled }, set: setCollecting))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("Screenshots Capture Explanation".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            Divider().padding(.horizontal, 12)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshots Folder".localized())
                    Text(folderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Show in Finder".localized(), action: revealFolder)
            }
            .padding(12)
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func setCollecting(_ isOn: Bool) { store.send(.captureToggleChanged(isOn)) }
    private func revealFolder() { store.send(.revealFolderTapped) }
}

#if DEBUG
struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
