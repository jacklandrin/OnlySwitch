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
    
    var body: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any switches on list".localized())
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack{
                    ForEach(customizeVM.allSwitches, id: \.type) { item in
                        CustomizeRowView(item: item, currentLang: langManager.currentLang)
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
}

private struct CustomizeRowView: View {
    @ObservedObject var item: CustomizeItem
    @ObservedObject private var preferencesvm = PreferencesObserver.shared
    let currentLang: String

    var body: some View {
        HStack {
            Toggle("", isOn: $item.toggle)
            if let iconImage = item.iconImage {
                Image(nsImage: iconImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
            }
            Text(item.barInfo.title.localized())
                .frame(width:170, alignment: .leading)
                .padding(.trailing, 10)
            KeyboardShortcuts.Recorder(for: item.keyboardShortcutName)
                .environment(\.locale, .init(identifier: currentLang))//Localizable follow system
            extraSettingsButton
                .padding(.leading, 10)

            Spacer()
        }
        .padding(.leading)
    }

    @ViewBuilder
    private var extraSettingsButton: some View {
        if item.type == .hideMenubarIcons {
            Button(action: {
                preferencesvm.preferences.menubarCollaspable.toggle()
            }, label: {
                if preferencesvm.preferences.menubarCollaspable {
                    Text("Disable".localized())
                } else {
                    Text("Enable".localized())
                }
            })
        } else if item.type == .radioStation || item.type == .backNoises {
            Button(action: {
                preferencesvm.preferences.radioEnable.toggle()
                if preferencesvm.preferences.radioEnable {
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
    }
}

#if DEBUG
struct CustomizeView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeView()
    }
}
#endif
