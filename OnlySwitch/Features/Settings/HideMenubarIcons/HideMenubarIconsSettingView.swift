//
//  HideMenubarIconsSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import SwiftUI

struct HideMenubarIconsSettingView: View {
    @StateObject var vm = HideMenubarIconsSettingVM()
    var body: some View {
        VStack(alignment: .leading) {
            Image("mark_icon_guide")
                .resizable()
                .scaledToFit()
            Text("When the switch is on, items in the left of the arrow-pointing icon are hidden. Hold ⌘ (command) and drag the icon to configure hidden section. This feature only works when the arrow-pointing icon is on the left side of App icon.".localized())
                .padding(.horizontal, 5)

            Text("The feature can be triggered when right clicking the arrow-pointing icon, and disabled by right clicking the App icon.".localized())
                .padding(.horizontal, 5)
                .padding(.vertical)
            Divider()
            Spacer()
            Group {
                HStack {
                    Text("Automatically hide icons after:".localized())
                    Menu(vm.converTimeDescription(duration: vm.automaticallyHideTime)) {
                        ForEach(vm.durationSet, id:\.self) { duration in
                            Button(vm.converTimeDescription(duration: duration)){
                                vm.automaticallyHideTime = duration
                            }
                        }
                    }.frame(width:150, height: 30)
                }.padding(.bottom, 20)

            }.padding(.horizontal)

        }
    }
}

#if DEBUG
struct HideMenubarIconsSettingView_Previews: PreviewProvider {
    static var previews: some View {
        HideMenubarIconsSettingView()
    }
}
#endif
