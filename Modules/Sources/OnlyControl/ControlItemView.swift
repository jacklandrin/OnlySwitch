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

    let viewState: ControlItemViewState

    public init(viewState: ControlItemViewState) {
        self.viewState = viewState
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
                VStack {
                    Image(nsImage: NSImage(data: viewState.iconData)!)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundColor(iconColor(isOn: viewState.status))

                    Text(viewState.title)
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .foregroundColor(textColor(isOn: viewState.status))
                    Text(String(viewState.id))
                }
            }
            .frame(width: 85, height: 85)
            .foregroundColor(
                backgroundColor(isOn: viewState.status)
            )
            .animation(.easeIn(duration: 0.2), value: viewState.status)
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
                title: "Long Long Control Item",
                iconData: NSImage(systemSymbolName: "gear")
                    .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                    .pngData!,
                type: .Switch
            )
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif
