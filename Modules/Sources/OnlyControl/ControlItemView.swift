//
//  ControlItemView.swift
//
//
//  Created by Jacklandrin on 2024/8/24.
//

import ComposableArchitecture
import SwiftUI
import AppKit
import Extensions
import Switches

public struct ControlItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State var isLargeSize = false
    let viewState: ControlItemViewState
    private let onActivate: (() -> Void)?
    private let onCopySubtitle: (() -> Void)?

    public init(viewState: ControlItemViewState, onActivate: (() -> Void)? = nil, onCopySubtitle: (() -> Void)? = nil) {
        self.viewState = viewState
        self.onActivate = onActivate
        self.onCopySubtitle = onCopySubtitle
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(.gray, lineWidth: 0.3)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .foregroundColor(backgroundColor(isOn: viewState.status))
                    .shadow(radius: 4)
            )
            .overlay {
                if viewState.copyableSubtitle, let subtitle = viewState.subtitle, let onCopySubtitle {
                    VStack(spacing: 3) {
                        Button { onActivate?() } label: {
                            iconAndTitle.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewState.title)
                        Button(action: onCopySubtitle) { subtitleLabel(subtitle) }
                            .buttonStyle(.plain)
                            .help("Copy".localized())
                            .accessibilityLabel("Copy".localized())
                            .accessibilityValue(subtitle)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                } else {
                    VStack(spacing: 3) {
                        iconAndTitle
                        if let subtitle = viewState.subtitle { subtitleLabel(subtitle) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { onActivate?() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(viewState.title)
                    .accessibilityValue(viewState.subtitle ?? "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onActivate?() }
                }
            }
            .frame(width: 85, height: 85)
            .foregroundColor(
                backgroundColor(isOn: viewState.status)
            )
            .animation(.easeIn(duration: 0.2), value: viewState.status)
    }

    private var iconAndTitle: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSImage(data: viewState.iconData)!)
                .renderingMode(viewState.usesTemplateIconRendering ? .template : .original)
                .resizable().scaledToFit()
                .frame(width: viewState.subtitle == nil ? 30 : 26, height: viewState.subtitle == nil ? 30 : 26)
                .foregroundStyle(iconColor(isOn: viewState.status))
                .accessibilityHidden(true)
            Text(viewState.title)
                .multilineTextAlignment(.center).font(.caption).lineLimit(2)
                .padding(.horizontal, 4)
                .foregroundStyle(textColor(isOn: viewState.status))
        }
    }

    private func subtitleLabel(_ subtitle: String) -> some View {
        Text(subtitle).multilineTextAlignment(.center).font(.caption).lineLimit(1)
            .minimumScaleFactor(0.65).padding(.horizontal, 4)
            .foregroundStyle(Color(nsColor: viewState.status ? .darkGray : .secondaryLabelColor))
    }

    private func backgroundColor(isOn: Bool) -> Color {
        switch (colorScheme, isOn) {
            case (.light, false):
                return .white.opacity(0.3)
            case (.dark, false):
                return Color(nsColor: .darkGray).opacity(0.4)
            default:
                return .white
        }
    }

    private func iconColor(isOn: Bool) -> Color {
        switch (colorScheme, isOn) {
            case (.light, false):
                return Color(nsColor: .darkGray)
            case (.dark, false):
                return Color(nsColor: .lightGray)
            default:
                return .accentColor
        }
    }

    private func textColor(isOn: Bool) -> Color {
        switch (colorScheme, isOn) {
            case (.light, false):
                return .black
            case (.dark, false):
                return .white
            default:
                return .accentColor
        }
    }
}

#if DEBUG
struct ControlItemView_Previews: PreviewProvider {
    static var previews: some View {
        ControlItemView(
            viewState: .init(
                id: "",
                title: "Long Long Control Item",
                iconData: NSImage(systemSymbolName: "gear")
                    .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                    .pngData!,
                controlType: .Switch
            )
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif
