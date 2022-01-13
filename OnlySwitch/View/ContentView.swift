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
    @State private var id = UUID()
    @State private var distanceY:CGFloat = 0
    @State private var movingIndex = 0
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing:0) {
                    ForEach(switchVM.allItemList.indices, id:\.self) { index in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20))
                                .frame(width: 30, height: 30)
                                .shadow(color: .gray, radius: 2, x: 0, y: 1)
                                .isHidden(isMoverHidden(index: index), remove: true)
                        
                            if let item = switchVM.allItemList[index] as? SwitchBarVM {
                                SwitchBarView().environmentObject(item)
                                    .frame(height:38)
                            } else if let item = switchVM.allItemList[index] as? ShortcutsBarVM {
                                ShortCutBarView().environmentObject(item)
                                    .frame(height:38)
                            }
                        }
                        .offset(y: itemOffsetY(index: index))
                        .gesture(
                            DragGesture()
                                .onChanged{ gesture in
                                    guard switchVM.sortMode else {return}
                                    
                                    movingIndex = index
                                    let locationY = gesture.location.y
                                    if self.distanceY == 0 && locationY != 0 {
                                        NSCursor.closedHand.set()
                                        print("set closeHand")
                                    }
                                    
                                    withAnimation{
                                        self.distanceY = locationY
                                    }
                                    
                                    if abs(self.distanceY) > 10 {
                                        let newIndex = movingIndex + Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / 38
                                        print("new index:\(newIndex), moving index:\(movingIndex), distance:\(self.distanceY)")
                                    }
                                }
                                .onEnded{ gesture in
                                    NSCursor.closedHand.pop()
                                    if abs(self.distanceY) > 10 {
                                        let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / 38
                                        
                                        var newIndex = index + indexOffset
                                        if newIndex < 0 {
                                            newIndex = 0
                                        } else if newIndex > switchVM.allItemList.count {
                                            newIndex = switchVM.allItemList.count
                                        }
                                        move(from: IndexSet(integer: index), to: newIndex )
                                        switchVM.saveOrder()
                                    }
                                    self.distanceY = 0
                                    movingIndex = 0
                                }
                        )
                        
                    }
                }
                .padding(.horizontal,15)
            }
            .frame(height: scrollViewHeight)
                .padding(.vertical,15)
            recommendApp.opacity(0.8)
            bottomBar
        }
        .background(
            VStack {
                Spacer()
                BluredSoundWave()
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .isHidden(!switchVM.soundWaveEffectDisplay || !playerItem.isPlaying, remove: true)
            }
        )
            .id(switchVM.updateID)
        .onReceive(NotificationCenter.default.publisher(for: showPopoverNotificationName, object: nil)) { _ in
            switchVM.refreshData()
        }
        .onReceive(NotificationCenter.default.publisher(for: changeSettingNotification, object: nil)) { _ in
            switchVM.refreshData()
        }
        .frame(height:scrollViewHeight + 130)
    }
    
    var recommendApp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
                        .frame(height: 45)
            HStack(spacing:5) {
//                Spacer()
                Text("More App, QRCobot".localized())
                    .font(.system(size: 14))
                    .fontWeight(.bold)
                    .padding(10)
                Spacer()
                Link(destination: URL(string: "https://apps.apple.com/us/app/wallcard/id1601311095")!, label: {
                    Image("WallCard")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 45)
                        .cornerRadius(10)
                        .help(Text("Download WallCard".localized()))
                })

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
            Button(action: {
                withAnimation {
                    switchVM.sortMode.toggle()
                }
            }, label: {
                Image(systemName: switchVM.sortMode ? "line.3.horizontal.circle.fill" : "line.3.horizontal.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Sort".localized()))
            
            Spacer()
            if playerItem.streamInfo == "" {
                HStack {
                    Text("Only Switch")
                        .fontWeight(.bold)
                        .padding(10)
                        
                    Text("v\(SystemInfo.majorVersion as! String)")
                        .offset(x:-10)
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
    
    
    var scrollViewHeight : CGFloat {
        let height = min(CGFloat((visableSwitchCount + switchVM.shortcutsList.count)) * 38.0 , switchVM.maxHeight - 150)
        print("scroll view height:\(height)")
        return height
    }
    
    var visableSwitchCount:Int {
        switchVM.switchList.filter{!$0.isHidden}.count
    }
    
    func move(from source: IndexSet, to destination: Int) {
        switchVM.allItemList.move(fromOffsets: source, toOffset: destination)
    }
    
    func itemOffsetY(index:Int) -> CGFloat {
        var newIndex = index
        if abs(self.distanceY) > 10 {
            let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / 38
            print("indexOffset:\(indexOffset)")
            newIndex = movingIndex + indexOffset
        }
        if newIndex < 0 {
            newIndex = 0
        } else if newIndex > switchVM.allItemList.count {
            newIndex = switchVM.allItemList.count
        }
       
        
        if movingIndex == index {
            return distanceY
        } else if (distanceY > 0 && index < newIndex && index > movingIndex) || (distanceY < 0 && index >= newIndex && index < movingIndex)  {
            return -38 * (distanceY / abs(distanceY))
        } else {
            return 0
        }
    }
    
    func currentCursor() -> NSCursor {
        if switchVM.sortMode {
            if distanceY != 0 {
                return NSCursor.closedHand
            } else {
                return NSCursor.openHand
            }
        } else {
            return NSCursor.arrow
        }
    }
    
    func isMoverHidden(index:Int) -> Bool {
        var hiddenSwitch = false
        if let item = switchVM.allItemList[index] as? SwitchBarVM {
            hiddenSwitch = item.isHidden
        }
        return !switchVM.sortMode || hiddenSwitch
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: popoverWidth, height: popoverHeight)
            .environmentObject(SwitchVM())
    }
}
