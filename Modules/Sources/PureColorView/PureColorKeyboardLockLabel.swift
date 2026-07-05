//
//  PureColorKeyboardLockLabel.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import Extensions
import SwiftUI

struct PureColorKeyboardLockLabel: View {
    @ObservedObject var vm: PureColorVM

    var body: some View {
        Text("Keyboard Locked ↓".localized())
            .fontWeight(.bold)
            .font(.system(size: 30))
            .foregroundColor(vm.currentColor == .white ? .black : .white)
            .opacity(vm.tipAlpha)
            .onHover(perform: updateHover)
            .padding(.bottom, 30)
    }

    private func updateHover(_ hover: Bool) {
        withAnimation {
            vm.isHovering = hover
        }
    }
}
