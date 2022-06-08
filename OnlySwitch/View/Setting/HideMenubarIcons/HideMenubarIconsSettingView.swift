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
            Text("When the switch is on, items in the left of the arrow-pointing icon are hidden. Hold ⌘ and drag the icon to configure hidden section.".localized())
                .padding(.horizontal, 5)
            Divider()
            Group {
                Toggle(isOn: $vm.isEnable, label: {
                    Text("Enable".localized())
                        .padding(.leading, 5)
                }).frame(height:30)
                HStack {
                    Text("Automatically hide icon after:".localized())
                    Menu(vm.converTimeDescription(duration: vm.automaticallyHideTime)) {
                        ForEach(vm.durationSet, id:\.self) { duration in
                            Button(vm.converTimeDescription(duration: duration)){
                                vm.automaticallyHideTime = duration
                            }
                        }
                    }.frame(width:150)
                }
                
            }.padding()
            
        }
    }
}

struct HideMenubarIconsSettingView_Previews: PreviewProvider {
    static var previews: some View {
        HideMenubarIconsSettingView()
    }
}
