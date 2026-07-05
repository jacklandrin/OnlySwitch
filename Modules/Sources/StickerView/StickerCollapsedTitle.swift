//
//  StickerCollapsedTitle.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import SwiftUI

struct StickerCollapsedTitle: View {
    let content: String
    let isCollapsed: Bool
    let strokeColor: Color
    let doubleTapAction: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(.clear)

            if isCollapsed {
                Text(Self.firstLine(in: content))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(strokeColor)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: doubleTapAction)
    }

    static func firstLine(in content: String) -> String {
        content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}
