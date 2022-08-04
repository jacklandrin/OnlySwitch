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
                        item.page
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
            
//            GeneralView()
            
        }.navigationTitle("Settings".localized())
        .onAppear{
            settingVM.selection = .General
        }
    }
    
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
    }
}
