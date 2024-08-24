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
    let store: StoreOf<ControlItemReducer>

    public init(store: StoreOf<ControlItemReducer>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.gray, lineWidth: 0.3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .foregroundColor(backgroundColor(isOn: store.status))
                        .shadow(radius: 4)
                )
                .overlay {
                    VStack {
                        Image(nsImage:NSImage(data: store.iconData)!)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(iconColor(isOn: store.status))

                        Text(store.title)
                            .multilineTextAlignment(.center)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .foregroundColor(textColor(isOn: store.status))
                    }
                }
                .frame(width: 74, height: 74)
                .foregroundColor(
                    backgroundColor(isOn: store.status)
                )
                .onTapGesture {
                    store.send(.didTap)
                }
                .animation(.easeIn, value: store.status)
        }
    }

    private func backgroundColor(isOn: Bool) -> Color {
        switch (colorScheme, isOn) {
            case (.light, false):
                return .white.opacity(0.3)
            case (.dark, false):
                return Color(nsColor: .darkGray).opacity(0.5)
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
            store: .init(
                initialState: .init(
                    title: "Long Long Control Item",
                    iconData: NSImage(systemSymbolName: "gear")
                        .resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!
                        .pngData!,
                    type: .Switch
                )
            ) {
                ControlItemReducer()
            }
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif
