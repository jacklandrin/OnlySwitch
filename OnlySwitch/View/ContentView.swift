//
//  ContentView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI
import LaunchAtLogin

struct ContentView: View {
    @EnvironmentObject var switchVM:SwitchVM
    @Environment(\.colorScheme) private var colorScheme
    @State private var switchList:[SwitchBarVM] = []
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
            recommendApp
            bottomBar
            
        }.id(id)
        .onReceive(NotificationCenter.default.publisher(for: showPopoverNotificationName, object: nil)) { _ in
            refreshData()
        }
        
    }
    
    var recommendApp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
                        .frame(height: 45)
            HStack() {
                Spacer()
                Text("More App, QRCobot")
                    .font(.system(size: 14))
                    .fontWeight(.bold)
                    .padding(10)
                Spacer()
                Link(destination: URL(string: "https://apps.apple.com/us/app/id1590006394")!, label: {
                    Image("QRCobot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 45)
                        .cornerRadius(10)
                        .help(Text("Download QRCobot"))
                })
            }.frame(height: 45)
                
        }.padding(.horizontal, 15)
    }
    
    var bottomBar : some View {
        HStack {
            Spacer()
            Text("Only Switch")
                .fontWeight(.bold)
                .padding(10)
                .offset(x:10)
            Spacer()
            Button(action: {
                switchVM.showSettingMenu.toggle()
            }, label: {
                Image(systemName: "gearshape.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .popover(isPresented: $switchVM.showSettingMenu) {
                    List {
                        LaunchAtLogin.Toggle {
                            Text("Start at login")
                        }
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
                    }
                    .frame(width: 150, height: 110)
                    
                }
                .padding(10)
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
