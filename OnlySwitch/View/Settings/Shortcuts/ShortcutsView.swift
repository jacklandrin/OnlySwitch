//
//  ShortcutsView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import SwiftUI
import AlertToast
import KeyboardShortcuts

struct ShortcutsView: View {
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    @StateObject var shortcutsVM = ShortcutsSettingVM()
    @ObservedObject var langManager = LanguageManager.sharedManager

    var body: some View {
        HStack(spacing:0) {
            
            VStack(alignment:.leading) {
                Text("To add or remove any shortcuts on list".localized())
                    .padding(10)
                Divider()
                    .frame(width: 380)
                if shortcutsVM.shortcutsList.count == 0 {
                    Spacer()
                    Text("There's not any Shortcuts.".localized())
                    Spacer()
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
                    }.frame(width: 400)
                }
            }
            VStack(spacing:0) {
                HStack {
                    Text("Shortcuts Gallery".localized())
                    Spacer()
                    Button(action: {
                        shortcutsVM.shouldLoadShortcutsList()
                        shortcutsVM.loadData()
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    }).help("refresh".localized())
                }
                .frame(width:300,height: 60)
                .padding(.trailing, 10)
                shortcutsMarket
            }
            
            Spacer()
        }
        .onAppear{
            shortcutsVM.shouldLoadShortcutsList()
            shortcutsVM.loadData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shortcutsVM.checkIfInstalled()
            }
        }
        .toast(isPresenting: $shortcutsVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: shortcutsVM.errorInfo.localized())
        }
    }
    
    var shortcutsMarket:some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(shortcutsVM.sharedShortcutsList.indices, id: \.self) { index in
                    VStack {
                        HStack{
                            Image("shortcuts_icon")
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
                        Spacer()
                        HStack {
                            Spacer()
                            Text("@\(shortcutsVM.sharedShortcutsList[index].author)")
                                .foregroundColor(.white)
                                .font(.system(size: 10))
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 5)
                    }.frame(width: 140, height: 100)
                        .background(LinearGradient(gradient: Gradient(colors:[Color(AppColor.themePink), Color(AppColor.themeBlue)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .help(shortcutsVM.sharedShortcutsList[index].description)
                    .cornerRadius(10)
                        .onTapGesture {
                            if shortcutsVM.sharedShortcutsList[index].hasInstalled {
                                _ = try? ShorcutsCMD.showShortcut(name: shortcutsVM.sharedShortcutsList[index].name).runAppleScript(isShellCMD: true)
                            }
                        }
                    }
                
            }
            .frame(width:300)
            .padding(.trailing, 10)
            Spacer()
        }
    }
}

#if DEBUG
struct ShortcutsView_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsView()
    }
}
#endif
