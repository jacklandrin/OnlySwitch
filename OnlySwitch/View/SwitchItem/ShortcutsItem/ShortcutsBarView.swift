//
//  ShortCutBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/2.
//

import SwiftUI

struct ShortcutsBarView: View {
    @EnvironmentObject var shortcutsBarVM:ShortcutsBarVM
    var body: some View {
        HStack {
            Image("shortcuts_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .padding(.trailing, 8)
            
            Text(shortcutsBarVM.barName)
                .frame(alignment: .leading)
            
            Spacer()
        
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
//                .scaleEffect(0.8)
                .isHidden(!shortcutsBarVM.processing,remove: true)
            
            Button(action: {
                shortcutsBarVM.runShortCut()
            }, label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .foregroundColor(.blue)
                        .frame(height:26)
                    Text("Run".localized())
                        .font(.system(size: "Run".localized().count > 6 ? 300 : 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.01)
                        .foregroundColor(.white)
                        .padding(1)
                }.frame(width: 46, height: 30)
            }).buttonStyle(.plain)
                .shadow(radius: 2)
                .padding(.horizontal, 6)

        }
    }
}

struct ShortCutBarView_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsBarView()
    }
}
