//
//  CustomizeView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import SwiftUI
import AlertToast
import KeyboardShortcuts

struct CustomizeView: View {
    @ObservedObject var customizeVM = CustomizeVM.shared
    @ObservedObject var langManager = LanguageManager.sharedManager
    var body: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any switches on list".localized())
                .padding(10)
            Divider()
            List {
                ForEach(customizeVM.allSwitches.indices, id:\.self) { index in
                    HStack {
                        Toggle("", isOn: $customizeVM.allSwitches[index].toggle)
                        Image(nsImage: barInfo(index: index).onImage.resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                        Text(barInfo(index:index).title.localized())
                            .frame(width:170, alignment: .leading)
                            .padding(.trailing, 10)
                        KeyboardShortcuts.Recorder(for: customizeVM.allSwitches[index].keyboardShortcutName)
                            .environment(\.locale, .init(identifier: langManager.currentLang))//Localizable doesn't work
                    }
                    .task {
                        KeyboardShortcuts.onKeyDown(for: customizeVM.allSwitches[index].keyboardShortcutName) {
                            customizeVM.allSwitches[index].doSwitch()
                        }
                    }
                    
                }
            }
            Divider()
                .padding(.bottom,10)
        }.toast(isPresenting: $customizeVM.showErrorToast) {
            AlertToast(displayMode: .alert,
                       type: .error(.red),
                       title: customizeVM.errorInfo.localized())
        }
        
    }
    
    func barInfo(index:Int) -> SwitchBarInfo {
        customizeVM.allSwitches[index].type.barInfo()
    }
}

struct CustomizeView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizeView()
    }
}
