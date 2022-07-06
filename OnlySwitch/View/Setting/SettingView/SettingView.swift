//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI

struct SettingView: View {
    @StateObject var settingVM = SettingVM()
    @ObservedObject var langManager = LanguageManager.sharedManager
    @ObservedObject var shortcutsVM = ShortcutsSettingVM.shared
    init() {
        settingVM.selection = settingVM.settingItems.first
    }
    var body: some View {
        NavigationView {
            List(settingVM.settingItems, id:\.self, selection: $settingVM.selection) { item in
                NavigationLink{
                    item.page()
                }label:{
                    Text(item.rawValue.localized())
                        .frame(minWidth: 190, alignment:.leading)
                        .lineLimit(2)
                }
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
