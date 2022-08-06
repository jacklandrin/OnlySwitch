//
//  GeneralView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import SwiftUI
import LaunchAtLogin

struct GeneralView: View, EmailProvider {
    @ObservedObject var langManager = LanguageManager.sharedManager
    @StateObject var generalVM = GeneralVM()
    @State var hoverItem = ""
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .trailing, spacing: Layout.generalSettingSpacing) {
                    Text("Launch:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                        
                    Text("Language:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    Text("Appearance:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Recommendation:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    Text("Menu Bar Icon:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    Text("Updates:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    Text("Cache:".localized())
                        .frame(height: 50, alignment: .top)
                        .padding(.top,5)
                    
                    Text("Contact:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    Text("Quit:".localized())
                        .frame(height:Layout.generalSettingItemHeight)
                }
                VStack(alignment: .leading, spacing: Layout.generalSettingSpacing) {
                    //launch at login
                    LaunchAtLogin.Toggle {
                        Text("Launch at login".localized())
                    }.frame(height:20)
                        .padding(.bottom,10)
                    
                    //languages
                    VStack {
                        MenuButton(label: Text(SupportedLanguages.getLangName(code: langManager.currentLang))) {
                            ForEach(generalVM.supportedLanguages, id:\.self) { lang in
                                Button(lang.name) {
                                    langManager.setCertainLang(lang.code)
                                }
                            }
                        }
                        .frame(maxWidth:150)
                    }.frame(height:Layout.generalSettingItemHeight)
                    
                    //Appearance
                    VStack {
                        MenuButton(label: Text(generalVM.currentAppearance.localized())) {
                            Button(SwitchListAppearance.single.rawValue.localized()) {
                                generalVM.currentAppearance = SwitchListAppearance.single.rawValue
                            }
                            
                            Button(SwitchListAppearance.dual.rawValue.localized()) {
                                generalVM.currentAppearance = SwitchListAppearance.dual.rawValue
                            }
                        }.frame(maxWidth:150)
                    }.frame(height:Layout.generalSettingItemHeight)
                    
                    //Recommendation
                    Toggle(isOn: $generalVM.showAds, label: {Text("Show Jack's App".localized())})
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    //menubar icons
                    Image(generalVM.currentMenubarIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width:22,height: 22)
                        .onTapGesture {
                            generalVM.showMenubarIconPopover = true
                        }
                        .popover(isPresented: $generalVM.showMenubarIconPopover, arrowEdge: .bottom) {
                            VStack {
                                ForEach(generalVM.menubarIcons, id:\.self) { iconName in
                                    HStack {
                                        Button(action: {
                                            generalVM.currentMenubarIcon = iconName
                                        }, label: {
                                            Image(iconName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width:22,height: 22)
                                        }).buttonStyle(PlainButtonStyle())
                                    }
                                    .frame(width:50)
                                    .background(hoverItem == iconName ? Color.blue : Color.clear)
                                    .onHover{_ in
                                        withAnimation {
                                            hoverItem = iconName
                                        }
                                    }
                                }
                            }.frame(width:50)
                                .padding(.vertical, 10)
                        }
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    //check update
                    HStack {
                        Button("Check for updates".localized()) {
                            generalVM.checkUpdate()
                        }
                        
                        if !generalVM.newestVersion.isEmpty {
                            if generalVM.isTheNewestVersion {
                                Text("You’re up to date!".localized())
                                    .foregroundColor(.green)
                            } else {
                                Text("The latest version is v%@".localizeWithFormat(arguments: generalVM.newestVersion))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
//                            .scaleEffect(0.6)
                            .isHidden(!generalVM.showProgress,remove: true)
                    }.frame(height:Layout.generalSettingItemHeight)
                    
                    
                    //clear cache
                    VStack(alignment:.leading,spacing: 15) {
                        HStack {
                            Text(generalVM.cacheSize)
                            Button("Clear cache".localized()) {
                                WallpaperManager.shared.clearCache()
                                generalVM.cacheSize = WallpaperManager.shared.cacheSize()
                            }
                        }
                        Text("Cache for Hide Notch Switch".localized())
                            .foregroundColor(.gray)
                    }.frame(height: 50)
                    
                    //feedback
                    Button("Send Email to Jacklandrin".localized()) {
                        sendEmail()
                    }
                    .frame(height:Layout.generalSettingItemHeight)
                   
                    //quit
                    Button("Quit Only Switch".localized()) {
                        NSApp.terminate(self)
                    }
                    .frame(height:Layout.generalSettingItemHeight)
                }
            }
        }
        .navigationTitle(Text("General".localized()))
        .onAppear{
            generalVM.cacheSize = WallpaperManager.shared.cacheSize()
        }
        .alert(isPresented: $generalVM.needtoUpdateAlert) {
            Alert(title: Text("Update".localized()),
                  message: Text("You can update to new version. The latest version is v%@".localizeWithFormat(arguments: generalVM.latestVersion)),
                  primaryButton: .default(Text("Download".localized()), action: {
                generalVM.downloadDMG()
            }),
                  secondaryButton:.default(Text("Cancel".localized())))
        }
    }
        
    
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
