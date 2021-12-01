//
//  ContentView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var switchVM:SwitchVM
    @Environment(\.colorScheme) private var colorScheme
    @State private var switchList:[SwitchOptionVM] = []
    @State private var showSettingMenu = false
    @State private var id = UUID()
    var body: some View {
        VStack {
            ScrollView(.vertical) {
                VStack {
                    ForEach(switchList.indices, id:\.self) { index in
                    
                        HStack {
                            Image(nsImage:
                                    barImage(option: switchList[index]))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25 , height: 25)
                            Text(switchList[index].switchType.switchTitle().title)
                            Spacer()
                            Toggle("",isOn: $switchList[index].isOn)
                                .toggleStyle(.switch)
                        }.isHidden(switchList[index].isHidden, remove: true)
                        
                    }
                    
                }.padding(15)
            }
            HStack {
                Spacer()
                Text("Only Switch")
                    .padding(10)
                    .offset(x:10)
                Spacer()
                Button(action: {
                    showSettingMenu.toggle()
                }, label: {
                    Image(systemName: "gearshape.circle")
                }).buttonStyle(.plain)
                    .popover(isPresented: $showSettingMenu) {
                        List {
                            Button(action: {
                                TopNotchSwitch.shared.clearCache()
                            }, label: {
                                Text("Clear cache")
                            }).buttonStyle(.borderless)
                            Divider()
                            Button(action: {
                                NSApp.terminate(self)
                            }, label: {
                                Text("Quit")
                            }).buttonStyle(.borderless)
                        }.frame(width: 150, height: 100)
                            
                    }
                    .padding(10)
            }
            
        }.id(id)
        .onReceive(NotificationCenter.default.publisher(for: showPopoverNotificationName, object: nil)) { _ in
            refreshData()
        }
        
    }

    func refreshData() {
        switchVM.refreshSwitchStatus()
        switchList = switchVM.switchList
        id = UUID()
    }
    
    func barImage(option:SwitchOptionVM) -> NSImage {
        if option.isOn {
            return option.switchType.switchTitle().onImage
        } else {
            return option.switchType.switchTitle().offImage
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().frame(width: 300).environmentObject(SwitchVM())
    }
}
