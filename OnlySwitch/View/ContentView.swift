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
    @State private var switchList:[SwitchBarVM] = []
    @State private var showSettingMenu = false
    @State private var id = UUID()
    var body: some View {
        VStack {
            ScrollView(.vertical) {
                VStack {
                    ForEach(switchList.indices, id:\.self) { index in
                        SwitchBarView().environmentObject(switchList[index])
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
        
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().frame(width: 300).environmentObject(SwitchVM())
    }
}
