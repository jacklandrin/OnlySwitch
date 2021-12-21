//
//  GeneralView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import SwiftUI
import LaunchAtLogin

struct GeneralView: View {
    @ObservedObject var langManager = LanguageManager.sharedManager
    @State var cacheSize:String = ""
    @State var needUpdate = false
    @State var showProgress = false
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .trailing, spacing: 25) {
                    Text("Launch:".localized())
                        .frame(height:20)
                        
                    Text("Language:".localized())
                        .frame(height:30)
                    
                    Text("Updates".localized())
                        .frame(height:30)
                    
                    Text("Cache:".localized())
                        .frame(height: 50, alignment: .top)
                    
                    Text("Contact:".localized())
                        .frame(height:30)
                    
                    Text("Quit:".localized())
                        .frame(height:30)
                }
                VStack(alignment: .leading, spacing: 25) {
                    LaunchAtLogin.Toggle {
                        Text("Launch at login".localized())
                    }.frame(height:20)
                        .padding(.bottom,10)
                
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
                        }
                        .frame(maxWidth:150)
                        
                    }
                    HStack {
                        Button("Check for updates") {
                            showProgress = true
                            CheckUpdateTool.shared.checkupdate(complete: { success in
                                if success {
                                    needUpdate = !CheckUpdateTool.shared.isTheNewestVersion()
                                    showProgress = false
                                }
                            })
                        }
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .isHidden(!showProgress,remove: true)
                    }
                    
                    VStack(alignment:.leading,spacing: 15) {
                        HStack {
                            Text(cacheSize)
                            Button("Clear cache".localized()) {
                                WallpaperManager.shared.clearCache()
                                cacheSize = WallpaperManager.shared.cacheSize()
                            }
                        }
                        Text("Cache for Hide Notch Switch".localized())
                            .foregroundColor(.gray)
                    }.frame(height: 50)
                    
                    Button("Send Email to Jacklandrin".localized()) {
                        SendEmail.send()
                    }
                    .frame(height:30)
                   
                    Button("Quit Only Switch".localized()) {
                        NSApp.terminate(self)
                    }
                    .frame(height:30)
                }
            }.padding(.top, 50)
            Spacer()
        }
        .onAppear{
            cacheSize = WallpaperManager.shared.cacheSize()
        }
        .alert(isPresented: $needUpdate) {
            Alert(title: Text("Update"),
                  message: Text("You can update to new Version. The latest version is v\(CheckUpdateTool.shared.latestVersion)"),
                  primaryButton: .default(Text("Download"), action: {
                CheckUpdateTool.shared.downloadDMG{ success, path in
                    guard success, let path = path else {return}
                    openDMG(path: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NSApp.terminate(self)
                    }
                }
            }),
                  secondaryButton:.cancel())
        }
    }
    
    func displayLang(lang:String) -> String {
        if lang == "en" {
            return "English"
        } else if lang == "zh-Hans" {
            return "简体中文"
        } else if lang == "de" {
            return "Deutsch"
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
