//
//  StickerCloseButton.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import SwiftUI

struct StickerCloseButton: View {
    let strokeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(strokeColor)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 5)
        .transition(.opacity)
    }
}
