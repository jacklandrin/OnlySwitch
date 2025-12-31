//
//  StickerReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import Foundation
import ComposableArchitecture
import Switches

@Reducer
struct StickerReducer {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: String
        var stickerContent = ""
        var isColorSelectorPresented = false
        var isHovering = false
        var stickerColor: StickerColor = .yellow
        var canTranslucent = false
        var previewMode = false
        var collaspeMode = false
        
        init(sticker: StickerModel) {
            self.id = sticker.id ?? UUID().uuidString
            self.stickerContent = sticker.content
            self.stickerColor = StickerColor.generateColor(from: sticker.color)
            self.canTranslucent = sticker.trancelucent ?? false
            self.previewMode = sticker.previewMode ?? false
            self.collaspeMode = sticker.collapseMode ?? false
        }
    }
    
    @CasePathable
    enum Action: BindableAction {
        case saveContent
        case showColorSelector
        case changeColor(StickerColor)
        case closeSticker
        case hover(Bool)
        case toggleTranslucent
        case togglePreviewMode
        case toggleCollapseMode
        case addSticker
        case binding(BindingAction<State>)
    }
    
    @Shared(.stickerCache) var stickerCache: [StickerModel]?
    
    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .saveContent:
                // Build a model from current state
                let model = StickerModel(
                    id: state.id,
                    content: state.stickerContent,
                    color: state.stickerColor.name,
                    trancelucent: state.canTranslucent,
                    previewMode: state.previewMode,
                    collapseMode: state.collaspeMode
                )

                // Persist to shared cache by id (update or append)
                $stickerCache.withLock { cache in
                    var arr = cache ?? []
                    if let idx = arr.firstIndex(where: { $0.id == state.id }) {
                        arr[idx] = model
                    }
                    cache = arr
                }
                return .none
                
            case .showColorSelector:
                state.isColorSelectorPresented = true
                return .none
                
            case .changeColor(let color):
                state.stickerColor = color
                state.isColorSelectorPresented = false
                return .send(.saveContent)
                
            case .closeSticker:
                $stickerCache.withLock { cache in
                    var arr = cache ?? []
                    arr.removeAll { $0.id == state.id }
                    cache = arr
                }
                return .none
                
            case .hover(let isHovering):
                state.isHovering = isHovering
                return .none
                
            case .toggleTranslucent:
                state.canTranslucent.toggle()
                return .send(.saveContent)
                
            case .togglePreviewMode:
                state.previewMode.toggle()
                return .send(.saveContent)
                
            case .toggleCollapseMode:
                state.collaspeMode.toggle()
                return .none
                
            case .addSticker:
                $stickerCache.withLock { $0?.append(StickerModel(color: StickerColor.allCases[Int.random(in: 0..<StickerColor.allCases.count)].name)) }
                return .none
                
            case .binding:
                return .none
            }
        }
    }
}
