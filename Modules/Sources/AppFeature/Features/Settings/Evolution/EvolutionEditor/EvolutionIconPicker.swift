//
//  EvolutionIconPicker.swift
//  OnlySwitch
//

import SwiftUI

/// A grid of SF Symbols for an Evolution's icon.
struct EvolutionIconPicker: View {
    let selected: String
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.iconNames, id: \.self) { name in
                    Button {
                        onSelect(name)
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 17))
                            .frame(width: 32, height: 32)
                            .background(
                                name == selected ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(name == selected ? .isSelected : [])
                }
            }
            .padding(12)
        }
        .frame(width: 260, height: 220)
    }

    static let iconNames = [
        "lightswitch.on.square", "button.programmable.square.fill", "externaldrive.fill.badge.timemachine",
        "moon.circle", "calendar.badge.clock", "person.crop.circle.badge.clock", "wand.and.rays.inverse",
        "slider.horizontal.3", "slider.horizontal.2.square.on.square", "slider.vertical.3", "power.circle",
        "keyboard", "globe", "sun.max.circle", "bag.circle", "creditcard", "dollarsign.circle",
        "hourglass.circle", "heart.circle", "cross.circle", "pill.circle", "location.circle",
        "arrow.up.arrow.down.circle", "arrow.left.arrow.right.circle", "arrowtriangle.forward.circle",
        "pause.circle", "stop.circle", "plus", "house", "lightbulb.circle", "balloon.2", "party.popper",
        "person.circle", "rectangle.badge.person.crop", "shield.lefthalf.filled", "lock", "lock.open", "key",
        "captions.bubble", "hare.fill", "tortoise.fill", "textformat.size", "minus.plus.batteryblock",
        "airplane.circle", "bolt.horizontal.circle", "network", "personalhotspot.circle",
        "antenna.radiowaves.left.and.right.circle", "externaldrive.connected.to.line.below", "wifi.circle",
        "gamecontroller", "squares.leading.rectangle", "arrow.clockwise.circle", "desktopcomputer", "sparkles"
    ]
}
