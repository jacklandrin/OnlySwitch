//
//  View+Erase.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/2.
//

import SwiftUI

public extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
