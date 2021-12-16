//
//  CustomizeView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import SwiftUI

struct CustomizeView: View {
    @ObservedObject var customizeVM = CustomizeVM()
    var body: some View {
        VStack(alignment:.leading) {
            Text("To add or remove any switches on list".localized())
                .padding(10)
            Divider()
            List {
                ForEach(customizeVM.allSwitches.indices, id:\.self) { index in
                    HStack {
                        Toggle("", isOn: $customizeVM.allSwitches[index].toggle)
                        Image(nsImage: barInfo(index: index).onImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                        Text(barInfo(index:index).title)
                    }
                    
                }
            }
            Divider()
                .padding(.bottom,10)
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
