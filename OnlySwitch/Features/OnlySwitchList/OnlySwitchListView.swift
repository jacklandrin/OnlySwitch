//
//  ContentView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Defines
import SwiftUI
import LaunchAtLogin
import Switches
import Utilities

enum Focusable: Hashable {
  case none
  case row(index: Int)
}

struct OnlySwitchListView: View {
    @EnvironmentObject var switchVM:SwitchListVM
    @Environment(\.colorScheme) private var colorScheme
    @State private var distanceY:CGFloat = 0
    @State private var movingIndex = -1
    @State private var hoverIndex = -1
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    @FocusState var focusedBar: Focusable?

    let columns = [
        GridItem(.fixed(Layout.popoverWidth - 40)),
        GridItem(.fixed(Layout.popoverWidth - 40))
    ]
    
    var body: some View {
        ZStack {
            VStack {
                Spacer()
                BluredSoundWave(width: listWidth, height: soundWaveHeight)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                    .isHidden(!switchVM.soundWaveEffectDisplay || !playerItem.isPlaying, remove: true)
            }
            VStack {
                bottomBar
                    .offset(y: 20)
                    .opacity(0.7)
                    .isHidden(SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single, remove: true)
                
                ScrollView {
                    if switchVM.currentAppearance == SwitchListAppearance.single.rawValue {
                        singleSwitchList
                    } else {
                        dualcolumnList
                    }
                    
                }
                .frame(height: scrollViewHeight)
                .padding(.vertical,15)
                .padding(.horizontal, 0)
                if switchVM.showAds {
                    recommendApp.opacity(0.8)
                }
                
                bottomBar
                    .isHidden(SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual, remove: true)
                
                Spacer().frame(height:SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual ? 20 : 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPopover, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changeSettings, object: nil)) { _ in
            Task {
                await switchVM.refreshData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSingleSwitchStatus, object: nil)) { n in
            if let type = n.object as? SwitchType {
                switchVM.refreshSingleSwitchStatus(type: type)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMenubarCollapse, object: nil)) { _ in
            switchVM.refreshSingleSwitchStatus(type: .hideMenubarIcons)
        }
        .frame(width: listWidth , height: scrollViewHeight + (switchVM.showAds ? 130 : 90))
    }
    
    var singleSwitchList: some View {
        VStack(spacing:0) {
            ForEach(switchVM.allItemList.indices, id:\.self) { index in
                VStack {
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .shadow(color: .gray, radius: 2, x: 0, y: 1)
                            .isHidden(isMoverHidden(index: index), remove: true)

                        if let item = switchVM.allItemList[index] as? SwitchBarVM {
                            SwitchBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        } else if let item = switchVM.allItemList[index] as? ShortcutsBarVM {
                            ShortcutsBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        } else if let item = switchVM.allItemList[index] as? EvolutionBarVM {
                            EvolutionBarView().environmentObject(item)
                                .frame(height: Layout.singleSwitchHeight)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 8)

                    Divider()
                        .opacity(0.25)
                        .frame(height: 1)
                }
                .background(
                    Color.accentColor
                    .shadow(color: Color(nsColor: .darkGray), radius: 1, x: 0, y: 1)
                    .opacity(0.15)
                    .isHidden(!itemHighlight(index: index))
                )
                .scaleEffect(itemScaleEffect(index: index))
                .focusReturnable(focusable: true, binding: $focusedBar, equals: .row(index: index)) {
                    if let item = switchVM.allItemList[index] as? SwitchBarVM {
                        item.switchType.doSwitch()
                    } else if let item = switchVM.allItemList[index] as? ShortcutsBarVM {
                        item.runShortCut()
                    } else if let item = switchVM.allItemList[index] as? EvolutionBarVM {
                        item.doSwitch()
                    }
                }
                .animation(.easeOut, value: focusedBar)
                .onHover{ isHovering in
                    if isHovering {
                        withAnimation(.easeOut) {
                            if #available(macOS 14.0, *) {
                                self.focusedBar = .row(index: index)
                            } else {
                                self.hoverIndex = index
                            }
                        }
                    }
                }
                .offset(y: itemOffsetY(index: index))
                .gesture(
                    DragGesture()
                        .onChanged{ gesture in
                            guard switchVM.sortMode else { return }

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
                                let newIndex = movingIndex + Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)
                                print("new index:\(newIndex), moving index:\(movingIndex), distance:\(self.distanceY)")
                            }
                        }
                        .onEnded{ gesture in
                            NSCursor.closedHand.pop()
                            if abs(self.distanceY) > 10 {
                                let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)

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
                            movingIndex = -1
                        }
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if !isHovering {
                hoverIndex = -1
            }
        }
    }
    
    var dualcolumnList: some View {
        VStack(spacing: 0) {
            if switchVM.uncategoryItemList.count > 0 {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.uncategoryItemList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.uncategoryItemList[index]
                            SwitchBarView().environmentObject(item)
                                    .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.audioItemList.count > 0 {
                HStack {
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                    Text("AUDIO".localized())
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                }.frame(height: 30)
                    .opacity(0.7)
                    .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.audioItemList.indices, id: \.self) { index in
                        HStack {
                            let item = switchVM.audioItemList[index]
                            SwitchBarView().environmentObject(item)
                                    .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            if switchVM.cleanupItemList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("CLEANUP".localized())
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                }.frame(height:30)
                    .opacity(0.7)
                    .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.cleanupItemList.indices, id: \.self) { index in
                        HStack {
                            let item = switchVM.cleanupItemList[index]
                            SwitchBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.toolItemList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("TOOLS".localized())
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.toolItemList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.toolItemList[index]
                            SwitchBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
            if switchVM.shortcutsList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    
                    Text("ACTIONS".localized())
                    
                    Rectangle().frame(height: 1)
                        .foregroundColor(.gray)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)
                
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.shortcutsList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.shortcutsList[index]
                            ShortcutsBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }

            if switchVM.evolutionList.count > 0 {
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                    Text("EVOLUTION")
                    Rectangle()
                        .frame(height: 1)
                }
                .frame(height:30)
                .opacity(0.7)
                .shadow(radius: 1)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(switchVM.evolutionList.indices, id:\.self) { index in
                        HStack {
                            let item = switchVM.evolutionList[index]
                            EvolutionBarView()
                                .environmentObject(item)
                                .frame(height:Layout.singleSwitchHeight)
                        }
                    }
                }
            }
            
        }
        .padding(.horizontal, 0)
    }
    
    var recommendApp: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
                .frame(height: 45)
            HStack(spacing:5) {
                ForEach(Ads) { ad in
                    Link(destination: URL(string: ad.link)!) {
                        Image(ad.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 45)
                            .cornerRadius(12)
                            .help(Text(ad.hint.localized()))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.gray, lineWidth: 1)
                                    .opacity(0.5)
                            )
                    }
                }
            }.frame(height: 45)
            
        }
        .padding(.horizontal, 15)
        .opacity(playerItem.isPlaying ? 0.5 : 1)
    }
    
    var bottomBar : some View {
        HStack {
            Button(action: {
                withAnimation {
                    switchVM.toggleSortMode()
                }
            }, label: {
                Image(systemName: switchVM.sortMode ? "line.3.horizontal.circle.fill" : "line.3.horizontal.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Sort".localized()))
                .isHidden(SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual)
            
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
                switchVM.showSettingsWindow()
            }, label: {
                Image(systemName: "gearshape.circle")
                    .font(.system(size: 17))
            }).buttonStyle(.plain)
                .padding(10)
                .help(Text("Settings".localized()))
        
        }
    }
    
    
    var scrollViewHeight: CGFloat {
        let switchCount = visableSwitchCount + switchVM.shortcutsList.count + switchVM.evolutionList.count
        var totalHeight = CGFloat(switchCount) * (Layout.singleSwitchHeight + 17)
        //two columns
        if switchVM.currentAppearance == SwitchListAppearance.dual.rawValue {
            totalHeight = categoryHeight(count: switchVM.uncategoryItemList.count)
            totalHeight += categoryHeight(count: switchVM.audioItemList.count)
            totalHeight += categoryHeight(count: switchVM.cleanupItemList.count)
            totalHeight += categoryHeight(count: switchVM.shortcutsList.count)
            totalHeight += categoryHeight(count: switchVM.toolItemList.count)
            totalHeight += categoryHeight(count: switchVM.evolutionList.count)
            totalHeight -= 30.0
        }
        
        let height = min(totalHeight, switchVM.maxHeight - 150)
        guard height > 0 else { return 300 }
        return height
    }
    
    func categoryHeight(count: Int) -> CGFloat {
        var height = 0.0
        if count > 0 {
            height += 30.0
            height += Double((count / 2)) * Layout.singleSwitchHeight
            if count % 2 == 1 {
                height += Layout.singleSwitchHeight
            }
        }
        return height
    }
    
    var visableSwitchCount:Int {
        return switchVM.switchList.filter{ !$0.isHidden }.count
    }
    
    func move(from source: IndexSet, to destination: Int) {
        switchVM.moveItem(from: source, to: destination)
    }
    
    var listWidth:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.popoverWidth : Layout.popoverWidth * 2 - 40
    }
    
    var soundWaveHeight:CGFloat {
        SwitchListAppearance(rawValue: switchVM.currentAppearance) == .single ? Layout.soundWaveHeight : Layout.soundWaveHeight / 2
    }
    
    func itemOffsetY(index:Int) -> CGFloat {
        var newIndex = index
        if abs(self.distanceY) > 10 {
            let indexOffset = Int(self.distanceY + 28 * (distanceY / abs(distanceY))) / Int(Layout.singleSwitchHeight)
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
            return -Layout.singleSwitchHeight * (distanceY / abs(distanceY))
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
    
    func itemScaleEffect(index:Int) -> CGFloat {
        if switchVM.sortMode {
            return index == movingIndex ? 1.008 : 1.0
        } else {
            if #available(macOS 14.0, *) {
                if focusedBar == .row(index: index) {
                    return 1.008
                } else {
                    return 1.0
                }
            } else {
                return index == hoverIndex ? 1.008 : 1.0
            }

        }
    }
    
    func itemHighlight(index:Int) -> Bool {
        if switchVM.sortMode {
            return index == movingIndex ? true : false
        } else {
            if #available(macOS 14.0, *) {
                return focusedBar == .row(index: index)
            } else {
                return index == hoverIndex
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        OnlySwitchListView()
            .frame(width: Layout.popoverWidth, height: Layout.popoverHeight)
            .environmentObject(SwitchListVM())
    }
}
#endif
