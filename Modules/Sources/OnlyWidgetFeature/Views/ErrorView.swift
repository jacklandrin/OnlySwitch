//
//  ErrorView.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/6/9.
//
import Defines
import SwiftUI

struct ErrorView: View {
    var unitType: UnitType = .evolution

    var body: some View {
        Link(destination: URL(string: "onlyswitch://SettingsWindow?destination=\(unitType.destination)")!, label: {
            Text("Please add a new %@ first.".localizeWithFormat(arguments: unitType.destination))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        .background(
            SpectrumView(unitType: unitType)
        )
    }
}

private extension UnitType {
    var destination: String {
        switch self {
        case .builtIn:
            return "Customize"
        case .shortcuts:
            return "Shortcuts"
        case .evolution:
            return "Evolution"
        }
    }
}
