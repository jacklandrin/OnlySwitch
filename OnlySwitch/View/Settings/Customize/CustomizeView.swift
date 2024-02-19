//
//  CustomizeView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import SwiftUI
import AlertToast
import KeyboardShortcuts
import Switches
import Utilities

struct CustomizeView: View {
    @ObservedObject var customizeVM = CustomizeVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    @ObservedObject var preferencesvm = PreferencesObserver.shared
    @State var preferences = PreferencesObserver.shared.preferences
    
    var body: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any switches on list".localized())
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack{
                    ForEach(customizeVM.allSwitches.indices, id:\.self) { index in
                        HStack {
                            Toggle("", isOn: $customizeVM.allSwitches[index].toggle)
                            Image(nsImage: barInfo(index: index).onImage!.resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                            Text(barInfo(index:index).title.localized())
                                .frame(width:170, alignment: .leading)
                                .padding(.trailing, 10)
                            KeyboardShortcuts.Recorder(for: customizeVM.allSwitches[index].keyboardShortcutName)
                                .environment(\.locale, .init(identifier: langManager.currentLang))//Localizable follow system
                            Group {
                                if customizeVM.allSwitches[index].type == .hideMenubarIcons {
                                    Button(action: {
                                        preferencesvm.preferences.menubarCollaspable = !preferences.menubarCollaspable
                                    }, label: {
                                        if preferencesvm.preferences.menubarCollaspable {
                                            Text("Disable".localized())
                                        } else {
                                            Text("Enable".localized())
                                        }
                                    })
                                } else if customizeVM.allSwitches[index].type == .radioStation || customizeVM.allSwitches[index].type == .backNoises {
                                    Button(action: {
                                        preferencesvm.preferences.radioEnable = !preferences.radioEnable
                                        if preferences.radioEnable {
                                            PlayerManager.shared.player.setupRemoteCommandCenter()
                                        } else {
                                            RadioStationSwitch.shared.playerItem.isPlaying = false
                                            PlayerManager.shared.player.clearCommandCenter()
                                        }
                                    }, label: {
                                        if preferencesvm.preferences.radioEnable {
                                            Text("Disable".localized())
                                        } else {
                                            Text("Enable".localized())
                                        }
                                    })
                                }
                            }.padding(.leading, 10)
                            
                            Spacer()
                        }.padding(.leading)
                    }
                }
                
            }
            Divider()
                .padding(.bottom,10)
        }
        .toast(isPresenting: $customizeVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: customizeVM.errorInfo.localized())
        }
        
    }
    
    func barInfo(index:Int) -> SwitchBarInfo {
        customizeVM.allSwitches[index].type.barInfo()
    }
}

#if DEBUG
struct CustomizeView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeView()
    }
}
#endif
