//
//  StickerBarButtons.swift
//  OnlySwitch
//
//  Created by OpenAI on 2026/7/5.
//

import ComposableArchitecture
import Extensions
import SwiftUI

struct StickerBarButtons: View {
    let store: StoreOf<StickerReducer>

    var body: some View {
        WithPerceptionTracking {
            HStack {
                Button(action: togglePreviewMode) {
                    Image(systemName: store.previewMode ? "eye" : "keyboard.badge.eye")
                        .foregroundStyle(strokeColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.previewMode ? "Edit".localized() : "Preview".localized())
                .opacity(store.collaspeMode ? 0 : 1)

                Button(action: toggleTranslucent) {
                    Image(store.canTranslucent ? "fill" : "translucent")
                        .foregroundStyle(strokeColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Translucent".localized())
                .opacity(store.collaspeMode ? 0 : 1)

                Button(action: showColorSelector) {
                    Image(systemName: "paintpalette")
                        .fontWeight(.bold)
                        .foregroundStyle(strokeColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Color".localized())

                Button(action: addSticker) {
                    Image(systemName: "plus")
                        .fontWeight(.bold)
                        .foregroundStyle(strokeColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add Sticker".localized())
            }
            .padding(.trailing, 5)
            .transition(.opacity)
        }
    }

    private var strokeColor: Color {
        Color(nsColor: store.stickerColor.stroke)
    }

    private func togglePreviewMode() {
        store.send(.togglePreviewMode, animation: .easeInOut)
    }

    private func toggleTranslucent() {
        store.send(.toggleTranslucent, animation: .easeInOut)
    }

    private func showColorSelector() {
        store.send(.showColorSelector, animation: .easeInOut)
    }

    private func addSticker() {
        store.send(.addSticker)
    }
}
