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
        Form {
            // MARK: - General Section
            Section {
                LaunchAtLogin.Toggle {
                    Text("Launch at login".localized())
                }
                
                Picker("Language:".localized(), selection: Binding(
                    get: { langManager.currentLang },
                    set: { newLang in
                        langManager.setCertainLang(newLang)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                )) {
                    ForEach(generalVM.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                
                Picker("Appearance:".localized(), selection: $generalVM.currentAppearance) {
                    Text(SwitchListAppearance.single.rawValue.localized())
                        .tag(SwitchListAppearance.single.rawValue)
                    Text(SwitchListAppearance.dual.rawValue.localized())
                        .tag(SwitchListAppearance.dual.rawValue)
                    Text(SwitchListAppearance.onlyControl.rawValue.localized())
                        .tag(SwitchListAppearance.onlyControl.rawValue)
                }
                .pickerStyle(.menu)
            } header: {
                Text("General".localized())
            }
            
            // MARK: - Menu Section
            Section {
                Toggle("Show More Apps".localized(), isOn: $generalVM.showAds)
                
                Toggle("Hide Menu after Running".localized(), isOn: $generalVM.hideMenuAfterRunning)
                
                HStack {
                    Text("Menu Bar Icon".localized())
                    Spacer()
                    Image(generalVM.currentMenubarIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .onTapGesture {
                            generalVM.showMenubarIconPopover = true
                        }
                        .popover(isPresented: $generalVM.showMenubarIconPopover, arrowEdge: .bottom) {
                            VStack {
                                ForEach(generalVM.menubarIcons, id: \.self) { iconName in
                                    HStack {
                                        Button(action: {
                                            generalVM.currentMenubarIcon = iconName
                                        }, label: {
                                            Image(iconName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 22, height: 22)
                                        }).buttonStyle(PlainButtonStyle())
                                    }
                                    .frame(width: 50)
                                    .background(hoverItem == iconName ? Color.blue : Color.clear)
                                    .onHover { _ in
                                        withAnimation {
                                            hoverItem = iconName
                                        }
                                    }
                                }
                            }
                            .frame(width: 50)
                            .padding(.vertical, 10)
                        }
                }
                
                HStack {
                    Text("Show List".localized())
                    Spacer()
                    KeyboardShortcuts.Recorder(for: generalVM.invokePopoverName)
                }
            } header: {
                Text("Menu".localized())
            }
            
            // MARK: - Updates Section
            Section {
                HStack {
                    Button("Check For Update...".localized()) {
                        generalVM.checkUpdate()
                    }
                    
                    Spacer()
                    
                    if !generalVM.newestVersion.isEmpty {
                        if generalVM.isTheNewestVersion {
                            Text("You're up to date!".localized())
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
                }
                
                Toggle("Check Updates on Launch".localized(), isOn: $generalVM.checkIfUpdateOnlaunch)
            } header: {
                Text("Updates".localized())
            }
            
            // MARK: - Cache Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Clear Cache".localized()) {
                            generalVM.clearCache()
                            generalVM.showCacheSize()
                        }
                        
                        Spacer()
                        
                        Text(generalVM.cacheSize)
                    }
                    Text("Cache for Hide Notch Switch".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Cache".localized())
            }
            
            // MARK: - About Section
            Section {
                Button("Send Email to Jacklandrin".localized()) {
                    sendEmail()
                }
                
                Button("Quit Only Switch".localized()) {
                    NSApp.terminate(self)
                }
            } header: {
                Text("About".localized())
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
        .onAppear {
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
