//
//  StickerReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import Foundation
import ComposableArchitecture

struct StickerReducer: Reducer {
    struct State: Equatable {
        var stickerContent = ""
        var isColorSelectorPresented = false
        var stickerColor: StickerColor = .yellow
    }

    enum Action: Equatable {
        case loadContent
        case editContent(String)
        case saveContent
        case showColorSelector
        case changeColor(StickerColor)
    }

    @Dependency(\.stickerService) var stickerService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .loadContent:
                    let sticker = stickerService.loadSticker()
                    state.stickerContent = sticker.content
                    state.stickerColor = sticker.color
                    return .none
                    
                case .editContent(let content):
                    state.stickerContent = content
                    return .none
                    
                case .saveContent:
                    stickerService.saveSticker(state.stickerContent, state.stickerColor)
                    return .none

                case .showColorSelector:
                    state.isColorSelectorPresented = true
                    return .none

                case .changeColor(let color):
                    state.stickerColor = color
                    state.isColorSelectorPresented = false
                    stickerService.saveSticker(state.stickerContent, state.stickerColor)
                    return .none
            }
        }
    }
}
