//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI

struct SettingView: View {
    @ObservedObject var settingVM = SettingVM()
    @ObservedObject var langManager = LanguageManager.sharedManager
    @ObservedObject var shortcutsVM = ShortcutsSettingVM.shared
    
    init() {
        settingVM.selection = settingVM.settingItems.first
    }
    var body: some View {
        NavigationView {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        item.page()
                    }label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
                HostingWindowFinder{ window in
                    if let window = window {
                        window.level = .popUpMenu + 1
                        NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                    }
                }.frame(width: 0, height: 0)
            }.listStyle(SidebarListStyle())
                .frame(minWidth:190)
            settingVM.settingItems.first?.page()
            
        }.navigationTitle("Settings".localized())
        .onAppear{
            settingVM.selection = settingVM.settingItems.first
        }
        .onDisappear{
            settingVM.onDisappear()
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
    }
}
