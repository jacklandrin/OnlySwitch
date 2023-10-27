//
//  FocusModifier.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/27.
//

import Foundation
import SwiftUI


extension View {
    @ViewBuilder
    func focusReturnable<Value>(focusable: Bool, binding: FocusState<Value>.Binding, equals value: Value, action: @escaping () -> Void) -> some View where Value : Hashable {
        if #available(macOS 14.0, *) {
            self
                .focusable(focusable, interactions: .automatic)
                .onKeyPress(.return) { 
                    action()
                    return .handled
                }
                .focusEffectDisabled()
                .focused(binding, equals: value)
        } else {
            self
        }
    }
}
