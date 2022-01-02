//
//  ShortcutsView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import SwiftUI
import AlertToast

struct ShortcutsView: View {
    @EnvironmentObject var shortcutsVM:ShortcutsSettingVM
    var body: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any shortcuts on list".localized())
                .padding(10)
            Divider()
            if shortcutsVM.shortcutsList.count == 0 {
                Text("There's not any Shortcuts.".localized())
            } else {
                List {
                    ForEach(shortcutsVM.shortcutsList.indices, id:\.self) { index in
                        HStack {
                            Toggle("", isOn: $shortcutsVM.shortcutsList[index].toggle)
                            Text(shortcutsVM.shortcutsList[index].name)
                        }
                    }
                }
            }
        }.toast(isPresenting: $shortcutsVM.showErrorToast) {
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
