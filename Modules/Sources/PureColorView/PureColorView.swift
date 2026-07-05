//
//  PureColorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import SwiftUI

public struct PureColorView: View {
    @ObservedObject var vm = PureColorVM()

    public init(exitScreenTestMode: @escaping @MainActor () -> Void = {}) {
        vm = PureColorVM(exitScreenTestMode: exitScreenTestMode)
    }

    public var body: some View {
        ZStack {
            PureColorOverlay(vm: vm)
            PureColorGuideLayer(vm: vm)
        }
            .background(vm.currentColor)
            .onAppear(perform: appear)
            .onDisappear(perform: disappear)
            .ignoresSafeArea()
    }

    private func appear() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation {
                if !vm.isHovering {
                    vm.tipAlpha = 0.0
                }
            }
        }
        vm.forbiddenKeyboard()
    }

    private func disappear() {
        vm.recoverKeyboard()
    }
}

#Preview {
    PureColorView()
}
