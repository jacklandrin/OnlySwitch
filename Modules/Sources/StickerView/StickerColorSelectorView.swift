//
//  StickerColorSelectorView.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import ComposableArchitecture
import Defines
import SwiftUI

struct StickerColorSelectorView: View {
    let store: StoreOf<StickerReducer>

    var body: some View {
        WithPerceptionTracking {
            VStack {
                HStack {
                    Spacer()
                    ForEach(StickerColor.allCases, id: \.self) { color in
                        Button(action: {
                            changeColor(color)
                        }) {
                            Circle()
                                .strokeBorder(Color(nsColor: color.stroke).opacity(0.5), lineWidth: 1)
                                .background(Circle().foregroundColor(Color(nsColor: color.bar)))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 16, height: 16)
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .background(
                    Color.white
                        .frame(height: 24)
                )
                Spacer()
            }
            .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.2), radius: 1)
            .transition(.move(edge: .top))
        }
    }

    private func changeColor(_ color: StickerColor) {
        store.send(.changeColor(color), animation: .easeOut)
    }
}
