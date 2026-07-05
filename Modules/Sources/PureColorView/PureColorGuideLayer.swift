//
//  PureColorGuideLayer.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import SwiftUI

struct PureColorGuideLayer: View {
    @ObservedObject var vm: PureColorVM

    var body: some View {
        ColorChangeGuide()
            .environmentObject(vm)
            .frame(width: 700, height: 700)
            .opacity(vm.tipAlpha)
            .onHover(perform: updateHover)
    }

    private func updateHover(_ hover: Bool) {
        withAnimation {
            vm.isHovering = hover
        }
    }
}
