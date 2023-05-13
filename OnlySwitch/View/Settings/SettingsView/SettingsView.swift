//
//  SettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI

struct SettingsView: View {
    @StateObject var settingVM = SettingsVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager

    var naviagtionView: some View {
        NavigationView {
            List(selection:$settingVM.selection) {
                ForEach(settingVM.settingItems, id:\.self ) { item in
                    NavigationLink{
                        item.page
                    } label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
                if #available(macOS 13.0, *) {
                    
                } else {
                    HostingWindowFinder{ window in
                        if let window = window {
                            NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                        }
                    }.frame(width: 0, height: 0)
                        .padding(0)
                }
            }.listStyle(.sidebar)
            if #available(macOS 13.0, *) {
                HostingWindowFinder{ window in
                    if let window = window {
                        NotificationCenter.default.post(name: .settingsWindowOpened, object: window)
                    }
                    settingVM.selection = .General
                }.frame(width: 0, height: 0)
                    .padding(0)
            }
        }.navigationTitle("Settings".localized())
            .toolbar {
                ToolbarItem(placement: .navigation) {
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
                        item.page
                    } label:{
                        Text(item.rawValue.localized())
                            .frame(minWidth: 190, alignment:.leading)
                            .lineLimit(2)
                    }
                }
            }.listStyle(.sidebar)
        }, detail: {
            GeneralView()
        })
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
