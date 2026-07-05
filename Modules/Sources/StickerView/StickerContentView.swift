//
//  StickerContentView.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import ComposableArchitecture
import SwiftUI

struct StickerContentView: View {
    @SwiftUI.Bindable var store: StoreOf<StickerReducer>

    var body: some View {
        WithPerceptionTracking {
            if store.previewMode {
                StickerMarkdownPreviewView(content: store.stickerContent)
            } else {
                TextEditor(text: $store.stickerContent)
                    .font(.system(size: 15))
                    .frame(minWidth: 200, minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.black)
                    .background(.clear)
            }
        }
    }
}
