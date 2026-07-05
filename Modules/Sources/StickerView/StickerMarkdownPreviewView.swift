//
//  StickerMarkdownPreviewView.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import MarkdownUI
import SwiftUI

struct StickerMarkdownPreviewView: View {
    let content: String

    var body: some View {
        ScrollView {
            Markdown(content)
                .markdownTextStyle {
                    FontFamily(.system())
                    FontSize(15)
                    FontWeight(.regular)
                    ForegroundColor(.black)
                    BackgroundColor(.clear)
                }
                .markdownTextStyle(\.code) {
                    BackgroundColor(.gray.opacity(0.3))
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(5)
                        .markdownTextStyle {
                            BackgroundColor(nil)
                        }
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(5)
                }
                .markdownBlockStyle(\.taskListMarker) { configuration in
                    Image(systemName: configuration.isCompleted ? "checkmark.circle.fill" : "circle")
                        .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
                }
                .markdownBlockStyle(\.table) { configuration in
                    configuration.label
                        .markdownTableBorderStyle(
                            TableBorderStyle(color: Color.black)
                        )
                }
                .padding(2)
        }
    }
}
