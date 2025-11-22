//
//  GeneralView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import Defines
import SwiftUI
import LaunchAtLogin
import AlertToast
import KeyboardShortcuts
import Utilities
import WidgetKit

struct GeneralView: View, EmailProvider {
    @ObservedObject var langManager = LanguageManager.sharedManager
    @StateObject var generalVM = GeneralVM()
    @State var hoverItem = ""
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .trailing, spacing: Layout.generalSettingSpacing) {
                    Text("Launch:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                        
                    Text("Language:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Appearance:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Promotion:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Switch Menu:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Menu Bar Icon:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Show List:".localized())
                        .frame(height: Layout.generalSettingItemHeight)

                    Text("Updates:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Check Updates".localized())
                        .frame(height: Layout.generalSettingItemHeight)

                    Text("Cache:".localized())
                        .frame(height: 50, alignment: .top)
                        .padding(.top, 5)
                    
                    Text("Contact:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                    
                    Text("Quit:".localized())
                        .frame(height: Layout.generalSettingItemHeight)
                }
                VStack(alignment: .leading, spacing: Layout.generalSettingSpacing) {
                    //launch at login
                    LaunchAtLogin.Toggle {
                        Text("Launch at login".localized())
                    }.frame(height: 20)
                        .padding(.bottom, 10)
                    
                    //languages
                    VStack {
                        MenuButton(label: Text(SupportedLanguages.getLangName(code: langManager.currentLang))) {
                            ForEach(generalVM.supportedLanguages, id:\.self) { lang in
                                Button(lang.name) {
                                    langManager.setCertainLang(lang.code)
                                    WidgetCenter.shared.reloadAllTimelines()
                                }
                            }
                        }
                        .frame(maxWidth: 150)
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

                            Button(SwitchListAppearance.onlyControl.rawValue.localized()) {
                                generalVM.currentAppearance = SwitchListAppearance.onlyControl.rawValue
                            }
                        }.frame(maxWidth: 150)
                    }.frame(height:Layout.generalSettingItemHeight)
                    
                    //Recommendation
                    Toggle(isOn: $generalVM.showAds) {
                        Text("Show More Apps".localized())
                    }
                    .frame(height: Layout.generalSettingItemHeight)
                    
                    //Hide Menu after Running
                    Toggle(isOn: $generalVM.hideMenuAfterRunning) {
                        Text("Hide Menu after Running".localized())
                    }
                    .frame(height: Layout.generalSettingItemHeight)
                    
                    //menubar icons
                    Image(generalVM.currentMenubarIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22,height: 22)
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
                                                .frame(width: 22, height:  22)
                                        }).buttonStyle(PlainButtonStyle())
                                    }
                                    .frame(width: 50)
                                    .background(hoverItem == iconName ? Color.blue : Color.clear)
                                    .onHover{_ in
                                        withAnimation {
                                            hoverItem = iconName
                                        }
                                    }
                                }
                            }.frame(width: 50)
                                .padding(.vertical, 10)
                        }
                        .frame(height:Layout.generalSettingItemHeight)
                    
                    //show list
                    KeyboardShortcuts.Recorder(for: generalVM.invokePopoverName)
                        .frame(height:Layout.generalSettingItemHeight)

                    //check update
                    HStack {
                        Button("Check For Update...".localized()) {
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
                            .isHidden(!generalVM.showProgress, remove: true)
                    }.frame(height: Layout.generalSettingItemHeight)
                    
                    //check update on launch
                    Toggle(
                        isOn: $generalVM.checkIfUpdateOnlaunch,
                        label: {
                            Text("Check Updates on Launch".localized())
                        }
                    )
                    .frame(height: Layout.generalSettingItemHeight)

                    //clear cache
                    VStack(alignment:.leading,spacing: 15) {
                        HStack {
                            Text(generalVM.cacheSize)
                            Button("Clear Cache".localized()) {
                                generalVM.clearCache()
                                generalVM.showCacheSize()
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
        .frame(minWidth: 500)
        .onAppear{
            generalVM.showCacheSize()
        }
        .toast(isPresenting: $generalVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: generalVM.errorInfo.localized())
        }
    }
        
    
}

#if DEBUG
struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
#endif
