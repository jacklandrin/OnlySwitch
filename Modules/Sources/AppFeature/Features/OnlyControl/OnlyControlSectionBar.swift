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
    @State private var widestTitleLabelWidth: CGFloat = 0

    private static let spacing: CGFloat = 4
    /// Breathing room a titled segment needs beyond its label's ideal width.
    private static let titleHorizontalPadding: CGFloat = 12

    static func showsTitles(
        widestLabelWidth: CGFloat,
        sectionCount: Int,
        availableWidth: CGFloat,
        spacing: CGFloat = spacing,
        horizontalPadding: CGFloat = titleHorizontalPadding
    ) -> Bool {
        guard sectionCount > 0, availableWidth > 0 else { return true }
        let spacingWidth = spacing * CGFloat(sectionCount - 1)
        let segmentWidth = (availableWidth - spacingWidth) / CGFloat(sectionCount)
        return widestLabelWidth + horizontalPadding <= segmentWidth
    }

    var body: some View {
        tabButtons
            .padding(2)
            .background(.black.opacity(0.08), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Only Control sections".localized())
    }

    private var tabButtons: some View {
        GeometryReader { proxy in
            let spacing = Self.spacing
            let showsTitles = Self.showsTitles(
                widestLabelWidth: widestTitleLabelWidth,
                sectionCount: sections.count,
                availableWidth: proxy.size.width
            )
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
                        sectionButton(section, showsTitle: showsTitles)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
        }
        .frame(height: 20)
        .background { titleWidthMeasurement }
        .onPreferenceChange(WidestTitleLabelWidthKey.self) { width in
            widestTitleLabelWidth = width
        }
    }

    /// Measures every titled label at its ideal width so the bar can fall back to icons only
    /// when the titles would otherwise be truncated.
    private var titleWidthMeasurement: some View {
        ZStack {
            ForEach(sections, id: \.self) { section in
                titledLabel(section)
                    .fixedSize()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: WidestTitleLabelWidthKey.self, value: proxy.size.width)
                        }
                    }
            }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func titledLabel(_ section: SectionBar.Section) -> some View {
        Label { Text(section.title) } icon: { SectionBarIcon(section: section, logoSize: 12) }
            .font(.caption2.weight(.medium))
    }

    private func sectionButton(_ section: SectionBar.Section, showsTitle: Bool) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.32)
            withAnimation(animation) {
                selection = section
            }
        } label: {
            titledLabel(section)
                .labelStyle(SectionLabelStyle(showsTitle: showsTitle))
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

private struct SectionLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
        } else {
            configuration.icon
        }
    }
}

private struct WidestTitleLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
