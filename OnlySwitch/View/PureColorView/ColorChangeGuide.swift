//
//  ColorChangeGuide.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/22.
//

import SwiftUI

struct ColorChangeGuide: View {
    @EnvironmentObject var vm:PureColorVM
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    vm.pressLeftButton()
                }, label: {
                    Image(systemName: "arrow.left.square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                }).buttonStyle(.plain)
                
                Spacer().frame(width:150)

                Button(action: {
                    vm.pressRightButton()
                }, label: {
                    Image(systemName: "arrow.right.square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                }).buttonStyle(.plain)
                
            }
            
            Text("Press left or right arrow button to change background color".localized())
                .font(Font.system(size: 15))
                .fontWeight(.bold)
                .padding(.top, 20)
        }.foregroundColor(vm.currentColor == .white ? .black : .white)
    }
}

struct ColorChangeGuide_Previews: PreviewProvider {
    static var previews: some View {
        ColorChangeGuide().environmentObject(PureColorVM())
    }
}
