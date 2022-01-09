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
    @ObservedObject var generalVM = GeneralVM()
    @State var hoverItem = ""
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .trailing, spacing: 15) {
                    Text("Launch:".localized())
                        .frame(height:20)
                        
                    Text("Language:".localized())
                        .frame(height:30)
                        .padding(.top,8)
                    
                    Text("Menu Bar Icon:".localized())
                        .frame(height:30)
                    
                    Text("Updates:".localized())
                        .frame(height:30)
                    
                    Text("Cache:".localized())
                        .frame(height: 50, alignment: .top)
                        .padding(.top,5)
                    
                    Text("Contact:".localized())
                        .frame(height:30)
                    
                    Text("Quit:".localized())
                        .frame(height:30)
                }
                VStack(alignment: .leading, spacing: 15) {
                    //launch at login
                    LaunchAtLogin.Toggle {
                        Text("Launch at login".localized())
                    }.frame(height:20)
                        .padding(.bottom,10)
                    
                    //languages
                    VStack {
                        MenuButton(label: Text(displayLang(lang:langManager.currentLang))) {
                            Button("English") {
                                langManager.setCertainLang("en")
                            }
                            Button("简体中文") {
                                langManager.setCertainLang("zh-Hans")
                            }
                            Button("Deutsch") {
                                langManager.setCertainLang("de")
                            }
                            Button("Hrvatski") {
                                langManager.setCertainLang("hr")
                            }
                        }
                        .frame(maxWidth:150)
                    }.frame(height:30)
                    
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
                        .frame(height:30)
                    
                    //check update
                    HStack {
                        Button("Check for updates".localized()) {
                            generalVM.showProgress = true
                            CheckUpdateTool.shared.checkupdate(complete: { success in
                                if success {
                                    generalVM.newestVersion = CheckUpdateTool.shared.latestVersion
                                    UserDefaults.standard.set(generalVM.newestVersion, forKey: newestVersionKey)
                                    UserDefaults.standard.synchronize()
                                    generalVM.needtoUpdateAlert = !CheckUpdateTool.shared.isTheNewestVersion()
                                }
                                generalVM.showProgress = false
                            })
                        }
                        
                        if !generalVM.newestVersion.isEmpty {
                            if CheckUpdateTool.shared.isTheNewestVersion() {
                                Text("You’re up to date!".localized())
                                    .foregroundColor(.green)
                            } else {
                                Text("The latest version is v%@".localizeWithFormat(arguments: generalVM.newestVersion))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .isHidden(!generalVM.showProgress,remove: true)
                    }.frame(height:30)
                    
                    
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
                    .frame(height:30)
                   
                    //quit
                    Button("Quit Only Switch".localized()) {
                        NSApp.terminate(self)
                    }
                    .frame(height:30)
                }
            }.padding(.top, 40)
            Spacer()
        }
        .onAppear{
            generalVM.cacheSize = WallpaperManager.shared.cacheSize()
        }
        .alert(isPresented: $generalVM.needtoUpdateAlert) {
            Alert(title: Text("Update".localized()),
                  message: Text("You can update to new version. The latest version is v%@".localizeWithFormat(arguments: CheckUpdateTool.shared.latestVersion)),
                  primaryButton: .default(Text("Download".localized()), action: {
                CheckUpdateTool.shared.downloadDMG{ success, path in
                    guard success, let path = path else {return}
                    openDMG(path: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NSApp.terminate(self)
                    }
                }
            }),
                  secondaryButton:.default(Text("Cancel".localized())))
        }
    }
    
    func displayLang(lang:String) -> String {
        if lang == "en" {
            return "English"
        } else if lang == "zh-Hans" {
            return "简体中文"
        } else if lang == "de" {
            return "Deutsch"
        } else if lang == "hr" {
            return "Hrvatski"
        }
        return ""
    }
    
    func openDMG(path:String) {
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: finder!, configuration: configuration, completionHandler: nil)
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
