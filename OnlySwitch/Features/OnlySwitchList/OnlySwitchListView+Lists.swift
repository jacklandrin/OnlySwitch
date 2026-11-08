//
//  OnlySwitchListView+Lists.swift
//  OnlySwitch
//

import AppKit
import Defines
import SwiftUI

extension OnlySwitchListView {
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
                            self.focusedBar = .row(index: index)
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
            if focusedBar == .row(index: index) {
                return 1.008
            } else {
                return 1.0
            }
        }
    }
    
    func itemHighlight(index:Int) -> Bool {
        if switchVM.sortMode {
            return index == movingIndex ? true : false
        } else {
            return focusedBar == .row(index: index)
        }
    }
}
