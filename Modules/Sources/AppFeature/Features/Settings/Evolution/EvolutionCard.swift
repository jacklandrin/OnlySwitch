//
//  EvolutionCard.swift
//  OnlySwitch
//

import SwiftUI

/// Liquid Glass on macOS 26, a regular material with a hairline border elsewhere.
private struct EvolutionCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(0.08)) }
        }
    }
}

extension View {
    func evolutionCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(EvolutionCardModifier(cornerRadius: cornerRadius))
    }

    /// The prominent action style: glass on macOS 26, bordered prominent before.
    @ViewBuilder
    func evolutionProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

extension CommandType {
    /// The title shown above a script in the editor.
    var editorTitle: String {
        switch self {
        case .on: "Turn on".localized()
        case .off: "Turn off".localized()
        case .status: "Check status".localized()
        case .single: "Run".localized()
        }
    }

    var scriptAccessibilityLabel: String {
        switch self {
        case .on: "Turn on script".localized()
        case .off: "Turn off script".localized()
        case .status: "Check status script".localized()
        case .single: "Button script".localized()
        }
    }
}

extension EvolutionItem {
    var displayIconName: String {
        iconName ?? (controlType == .Button ? "button.programmable.square.fill" : "lightswitch.on.square")
    }
}
