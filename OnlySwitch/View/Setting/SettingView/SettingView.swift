//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI

struct SettingView: View {
    @StateObject var settingVM = SettingVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    @ObservedObject var shortcutsVM = ShortcutsSettingVM.shared
    

    var body: some View {
        NavigationView {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        page
                    }label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
                HostingWindowFinder{ window in
                    if let window = window {
                        NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                    }
                }.frame(width: 0, height: 0)
            }.listStyle(SidebarListStyle())
                .frame(minWidth:190)
            
            GeneralView()
            
        }.navigationTitle("Settings".localized())
        .onAppear{
            settingVM.selection = .General
        }
    }
    
    private var page : some View {
        switch settingVM.selection! {
        case .AirPods:
            return AirPodsSettingView().eraseToAnyView()
        case .Radio:
            return RadioSettingView().eraseToAnyView()
        case .PomodoroTimer:
            return PomodoroTimerSettingView().eraseToAnyView()
        case .Shortcuts:
            return ShortcutsView().eraseToAnyView()
        case .General:
            return GeneralView().eraseToAnyView()
        case .Customize:
            return CustomizeView().eraseToAnyView()
        case .HideMenubarIcons:
            return HideMenubarIconsSettingView().eraseToAnyView()
        case .About:
            return AboutView().eraseToAnyView()
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
    }
}
