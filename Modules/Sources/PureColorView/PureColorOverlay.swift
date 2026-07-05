//
//  PureColorOverlay.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import SwiftUI

struct PureColorOverlay: View {
    @ObservedObject var vm: PureColorVM

    var body: some View {
        VStack {
            HStack {
                PureColorCloseButton(vm: vm)
                Spacer()
            }
            Spacer()
            PureColorKeyboardLockLabel(vm: vm)
        }
    }
}
