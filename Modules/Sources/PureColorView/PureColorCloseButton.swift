//
//  PureColorCloseButton.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import SwiftUI

struct PureColorCloseButton: View {
    @ObservedObject var vm: PureColorVM

    var body: some View {
        Button(action: vm.exitScreenTestMode) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundColor(vm.currentColor == .white ? .black : .white)
                .opacity(vm.tipAlpha)
        }
        .buttonStyle(.borderless)
        .shadow(radius: 3)
        .onHover(perform: updateHover)
        .padding(20)
    }

    private func updateHover(_ hover: Bool) {
        withAnimation {
            vm.isHovering = hover
        }
    }
}
