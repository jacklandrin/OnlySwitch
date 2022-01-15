//
//  ShortcutsView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import SwiftUI
import AlertToast
import KeyboardShortcuts

let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

struct ShortcutsView: View {
    @EnvironmentObject var shortcutsVM:ShortcutsSettingVM
    @ObservedObject var langManager = LanguageManager.sharedManager

    var body: some View {
        HStack(spacing:0) {
            
            VStack(alignment:.leading) {
                Text("To add or remove any shortcuts on list".localized())
                    .padding(10)
                Divider()
                    .frame(width: 360)
                if shortcutsVM.shortcutsList.count == 0 {
                    Text("There's not any Shortcuts.".localized())
                } else {
                    List {
                        ForEach(shortcutsVM.shortcutsList.indices, id:\.self) { index in
                            HStack {
                                Toggle("", isOn: $shortcutsVM.shortcutsList[index].toggle)
                                Text(shortcutsVM.shortcutsList[index].name)
                                    .frame(width: 170, alignment: .leading)
                                    .padding(.trailing, 10)
                                
                                KeyboardShortcuts.Recorder(for: shortcutsVM.shortcutsList[index].keyboardShortcutName)
                                    .environment(\.locale, .init(identifier: langManager.currentLang))//Localizable doesn't work
                                
                                Spacer().frame(width:30)
                            }
                        }
                    }.frame(width: 380)
                }
            }
            VStack {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(shortcutsVM.sharedShortcutsList.indices, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .frame(width: 120, height: 80)
                                .foregroundColor(.blue)
                            VStack {
                                HStack{
                                    Image(systemName: "square.2.stack.3d")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        
                                    Spacer()
                                    Button(action: {
                                        NSWorkspace.shared.open(URL(string: shortcutsVM.sharedShortcutsList[index].link)!)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                            shortcutsVM.checkIfInstalled()
                                        }
                                    }, label: {
                                        Image(systemName: shortcutsVM.sharedShortcutsList[index].hasInstalled ? "checkmark.circle.fill" : "plus.circle.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                    }).buttonStyle(.plain)
                                        .disabled(shortcutsVM.sharedShortcutsList[index].hasInstalled)
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                
                                Spacer(minLength: 10)
                                
                                Text(shortcutsVM.sharedShortcutsList[index].name)
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 5)
                                Spacer()
                            }.frame(width: 120, height: 80)
                                
                                .onTapGesture {
                                    if shortcutsVM.sharedShortcutsList[index].hasInstalled {
                                        _ = showShortcut(name: shortcutsVM.sharedShortcutsList[index].name).runAppleScript(isShellCMD: true)
                                    }
                                }
                        }
                    }
                }.frame(width:280)
                    .padding(.top, 60)
                Spacer()
            }
            Spacer()
        }
        .toast(isPresenting: $shortcutsVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: shortcutsVM.errorInfo.localized())
        }
    }
}

struct ShortcutsView_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsView()
    }
}
