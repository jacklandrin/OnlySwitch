//
//  ShortcutsView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import SwiftUI
import AlertToast
import Defines
import KeyboardShortcuts
import Switches
import Utilities

struct ShortcutsView: View {
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)]
    @StateObject var shortcutsVM = ShortcutsSettingVM()
    @ObservedObject var langManager = LanguageManager.sharedManager
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing:0) {
                installedShortcutsSection
                    .frame(width: min(geometry.size.width * 0.6, 600))
                gallerySection
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear{
            shortcutsVM.shouldLoadShortcutsList()
            shortcutsVM.loadData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shortcutsVM.checkIfInstalled()
            }
        }
        .toast(isPresenting: $shortcutsVM.showErrorToast) {
            AlertToast(
                displayMode: .alert,
                type: .error(.red),
                title: shortcutsVM.errorInfo.localized()
            )
        }
    }
    
    @ViewBuilder
    var installedShortcutsSection: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any shortcuts on list".localized())
                .padding(10)
            Divider()
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
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                                .help(shortcutsVM.shortcutsList[index].name)
                            
                            KeyboardShortcuts.Recorder(for: shortcutsVM.shortcutsList[index].keyboardShortcutName)
                                .environment(\.locale, .init(identifier: langManager.currentLang))//Localizable doesn't work
                            
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var gallerySection: some View {
        VStack(spacing:0) {
            HStack {
                Text("Shortcuts Gallery".localized())
                Spacer()
                Button(action: {
                    shortcutsVM.shouldLoadShortcutsList()
                    shortcutsVM.loadData()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("refresh".localized())
            }
            .frame(height: 60)
            .padding(.trailing, 10)
            shortcutsMarket
        }
    }
    
    var shortcutsMarket: some View {
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
                            Button {
                                NSWorkspace.shared.open(URL(string: shortcutsVM.sharedShortcutsList[index].link)!)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                    shortcutsVM.checkIfInstalled()
                                }
                            } label: {
                                Image(systemName: shortcutsVM.sharedShortcutsList[index].hasInstalled ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.white)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .disabled(shortcutsVM.sharedShortcutsList[index].hasInstalled)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        
                        Spacer(minLength: 10)
                        
                        Text(shortcutsVM.sharedShortcutsList[index].name)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                        Spacer()
                        HStack {
                            Spacer()
                            Text("@\(shortcutsVM.sharedShortcutsList[index].author)")
                                .foregroundColor(.white)
                                .font(.system(size: 10))
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 5)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color(.themeLila))
                    .help(shortcutsVM.sharedShortcutsList[index].description)
                    .cornerRadius(10)
                    .onTapGesture {
                        Task {
                            if shortcutsVM.sharedShortcutsList[index].hasInstalled {
                                _ = try? await ShorcutsCMD.showShortcut(name: shortcutsVM.sharedShortcutsList[index].name).runAppleScript(isShellCMD: true)
                            }
                        }
                    }
                }
                
            }
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
