//
//  OnlyControlSectionBar.swift
//  OnlySwitch
//

import SwiftUI

struct OnlyControlSectionBar: View {
    let sections: [SectionBar.Section]
    @Binding var selection: SectionBar.Section
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        tabButtons
            .padding(2)
            .background(.black.opacity(0.08), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Only Control sections".localized())
    }

    private var tabButtons: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let spacingWidth = spacing * CGFloat(max(0, sections.count - 1))
            let segmentWidth = max(0, (proxy.size.width - spacingWidth) / CGFloat(max(1, sections.count)))
            let selectedIndex = sections.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                selectionIndicator
                    .frame(width: segmentWidth, height: 20)
                    .offset(x: CGFloat(selectedIndex) * (segmentWidth + spacing))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(spacing: spacing) {
                    ForEach(sections, id: \.self) { section in
                        sectionButton(section)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
        }
        .frame(height: 20)
    }

    private func sectionButton(_ section: SectionBar.Section) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.32)
            withAnimation(animation) {
                selection = section
            }
        } label: {
            Label { Text(section.title) } icon: { SectionBarIcon(section: section, logoSize: 12) }
                .font(.caption2.weight(.medium))
                .foregroundStyle(selection == section ? selectedForegroundStyle : .secondary)
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityHint("Shows the %@ section".localizeWithFormat(arguments: section.title))
        .help(Text(section.title))
    }

    private var selectedForegroundStyle: Color {
        colorScheme == .dark ? .white : .primary
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.16)), in: Capsule())
        } else {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
        }
    }
}
