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
    @State private var shortcutList:[ShortcutsBarVM] = []
    @State private var id = UUID()
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing:0) {
                    ForEach(switchList.indices, id:\.self) { index in
                        SwitchBarView().environmentObject(switchList[index])
                            .frame(height:38)
                    }
                    ForEach(shortcutList.indices, id:\.self) { index in
                        ShortCutBarView().environmentObject(shortcutList[index])
                            .frame(height:38)
                    }
                }.padding(.horizontal,15)
            }.frame(height: scrollViewHeight)
                .padding(.vertical,15)
            recommendApp.opacity(0.8)
            bottomBar

        }.background(
            VStack {
                Spacer()
                BluredSoundWave()
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .isHidden(!switchVM.soundWaveEffectDisplay || !playerItem.isPlaying, remove: true)
            }
        )
        .id(id)
        .onReceive(NotificationCenter.default.publisher(for: showPopoverNotificationName, object: nil)) { _ in
            refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: changeSettingNotification, object: nil)) { _ in
            refreshData()
        }
        .frame(height:scrollViewHeight + 130)
    }
    
    var recommendApp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
                        .frame(height: 45)
            HStack() {
                Spacer()
                Text("More App, QRCobot".localized())
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
                        .help(Text("Download QRCobot".localized()))
                })
            }.frame(height: 45)
                
        }.padding(.horizontal, 15)
    }
    
    var bottomBar : some View {
        HStack {
            Spacer()
            if playerItem.streamInfo == "" {
                HStack {
                    Text("Only Switch")
                        .fontWeight(.bold)
                        .padding(10)
                        .offset(x:10)
                    Text("v\(SystemInfo.majorVersion as! String)")
                }
                .transition(.move(edge: .bottom))
                
            } else {
                RollingText(text: playerItem.streamInfo,
                            leftFade: 16,
                            rightFade: 16,
                            startDelay: 3)
                    .frame(height:20)
                    .padding(10)
                    .transition(.move(edge: .bottom))
            }
            
            
            Spacer()
            Button(action: {
                OpenWindows.Setting.open()
                NotificationCenter.default.post(name: shouldHidePopoverNotificationName, object: nil)
            }, label: {
                Image(systemName: "gearshape.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Settings".localized()))
        }
    }
    
    func refreshData() {
        switchVM.refreshList()
        switchVM.refreshSwitchStatus()
        switchList = switchVM.switchList
        shortcutList = switchVM.shortcutsList
        id = UUID()
        print("refresh")
    }
    
    var scrollViewHeight : CGFloat {
        let height = min(CGFloat((visableSwitchCount + shortcutList.count)) * 38.0 , switchVM.maxHeight - 150)
        print("scroll view height:\(height)")
        return height
    }
    
    var visableSwitchCount:Int {
        switchList.filter{!$0.isHidden}.count
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: popoverWidth, height: popoverHeight)
            .environmentObject(SwitchVM())
    }
}
