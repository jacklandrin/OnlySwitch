//
//  StickerCollapsedTitle.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import Extensions
import SwiftUI

struct StickerCollapsedTitle: View {
    let content: String
    let isCollapsed: Bool
    let strokeColor: Color
    let doubleTapAction: () -> Void

    var body: some View {
        ZStack {
            WindowDragView(onDoubleClick: doubleTapAction)

            if isCollapsed {
                Text(Self.firstLine(in: content))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(strokeColor)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
    }

    static func firstLine(in content: String) -> String {
        content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}
