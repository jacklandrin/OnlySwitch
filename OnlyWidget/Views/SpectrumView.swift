//
//  SpectrumView.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/6/9.
//

import Defines
import SwiftUI

struct SpectrumView: View {
    var unitType: UnitType
    private var colors: [Color] = [.red, .yellow, .green, .blue, .purple, .red]

    init(unitType: UnitType) {
        self.unitType = unitType
        if unitType == .evolution {
            colors = [.pink, .orange, .yellow, .mint, .cyan, .indigo, .pink]
        }
    }

    var body: some View {
        AngularGradient(
            gradient: Gradient(colors: colors),
            center: .center
        )
        .modify {
            if unitType == .evolution {
                $0
                    .saturation(0.9)
                    .brightness(0.35)
            }
        }
        .opacity(0.2)
    }
}
