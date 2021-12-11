//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI

struct SettingView: View {
    @ObservedObject var settingVM = SettingVM()
    init() {
        settingVM.selection = settingVM.settingItems.first
    }
    var body: some View {
        NavigationView {
            List(settingVM.settingItems, id:\.self, selection: $settingVM.selection) { item in
                NavigationLink{
                    item.page()
                }label:{
                    Text(item.rawValue)
                }
            }.listStyle(SidebarListStyle())
            settingVM.settingItems.first?.page()
        }.onAppear{
            settingVM.selection = settingVM.settingItems.first
        }
        .onDisappear{
            print("disappear")
            NSApplication.shared.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first!.makeKeyAndOrderFront(self)
            }
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
    }
}
