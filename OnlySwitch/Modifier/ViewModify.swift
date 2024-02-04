//
//  ViewModify.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/2/4.
//

import SwiftUI

extension View {
    @ViewBuilder
    func modify(@ViewBuilder _ transform: (Self) -> (some View)?) -> some View {
        if let view = transform(self), !(view is EmptyView) {
            view
        } else {
            self
        }
    }
}
