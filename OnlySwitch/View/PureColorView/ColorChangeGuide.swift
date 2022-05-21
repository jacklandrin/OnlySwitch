//
//  ColorChangeGuide.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/22.
//

import SwiftUI

struct ColorChangeGuide: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "arrow.up.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
            }
            HStack {
                Image(systemName: "arrow.left.square.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.down.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.right.square.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
            }
        }
    }
}

struct ColorChangeGuide_Previews: PreviewProvider {
    static var previews: some View {
        ColorChangeGuide()
    }
}
