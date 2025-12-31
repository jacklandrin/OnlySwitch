//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import Utilities
import OnlyAgent

struct SettingsView: View {
    @StateObject var settingVM = SettingsVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager

    init(settingItem: Binding<SettingsItem?> = .constant(nil)) {
        if let item = settingItem.wrappedValue {
            settingVM.selection = item
        }
    }

    var naviagtionView: some View {
        NavigationView {
            List(selection: $settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        page(item: item)
                            .navigationTitle(item.rawValue.localized())
                    } label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
                HostingWindowFinder{ window in
                    if let window = window {
                        NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                    }
                }
                .frame(width: 0, height: 0)
                .padding(0)
                
            }.listStyle(.sidebar)
            
            HostingWindowFinder{ window in
                if let window = window {
                    NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                }
                settingVM.selection = .General
            }.frame(width: 0, height: 0)
                .padding(0)
            
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
    func naviagtionSplitView() -> some View {
        NavigationSplitView(sidebar: {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        page(item: item)
                            .navigationTitle(item.rawValue.localized())
                    } label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.sidebar)
        }, detail: {
            GeneralView()
        })
    }

    @ViewBuilder
    func page(item: SettingsItem) -> some View {
        switch item {
            case .AirPods:
                AirPodsSettingView()

            case .Radio:
                RadioSettingView()

            case .PomodoroTimer:
                PomodoroTimerSettingView()

            case .Shortcuts:
                ShortcutsView()

            case .General:
                GeneralView()

            case .Customize:
                CustomizeView()

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
            
            case .NightShift:
                NightShiftSettingsView()

            case .KeyLight:
                KeyLightView(store: settingVM.keyLightStore)

            case .About:
                AboutView()
        }
    }

    var body: some View {
        if #available(macOS 13.3, *) {
            naviagtionSplitView()
        } else {
            naviagtionView
        }
    }

}

#if DEBUG
struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
