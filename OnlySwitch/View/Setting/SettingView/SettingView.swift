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
    @ObservedObject var shortcutsVM = ShortcutsSettingVM()
    init() {
        settingVM.selection = settingVM.settingItems.first
    }
    var body: some View {
        NavigationView {
            List(settingVM.settingItems, id:\.self, selection: $settingVM.selection) { item in
                NavigationLink{
                    if item == .Shortcuts {
                        item
                            .page()
                            .environmentObject(shortcutsVM)
                            .onAppear{
                                shortcutsVM.loadShortcutsList()
                            }
                            
                    } else {
                        item.page()
                    }
                    
                }label:{
                    Text(item.rawValue.localized())
                }.frame(width:170, alignment:.leading)
            }.listStyle(SidebarListStyle())
                .frame(width:170)
            settingVM.settingItems.first?.page()
        }.navigationTitle("Setting")
        .onAppear{
            settingVM.selection = settingVM.settingItems.first
            shortcutsVM.loadShortcutsList()
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
