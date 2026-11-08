//
//  OnlySwitchListView+BottomBar.swift
//  OnlySwitch
//

import AppKit
import Design
import SwiftUI

extension OnlySwitchListView {
    var recommendApp: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Ads) { ad in
                    Button {
                        if let qrcode = ad.qrcode {
                            QRCodeWindowController.shared.show(url: qrcode)
                        } else if let link = ad.link {
                            NSWorkspace.shared.open(link)
                        }
                    } label: {
                        AsyncImage(url: ad.imageURL) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "app.dashed")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 45)
                        .cornerRadius(12)
                        .help(Text(ad.hint.localized()))
                        .accessibilityLabel(ad.hint.localized())
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.gray, lineWidth: 1)
                                .opacity(0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 45)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .foregroundColor(colorScheme == .dark ? Color(nsColor: NSColor.darkGray) : .white)
        )
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
                .isHidden(selectedSection != .controls || SwitchListAppearance(rawValue: switchVM.currentAppearance) == .dual)
            
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
}
