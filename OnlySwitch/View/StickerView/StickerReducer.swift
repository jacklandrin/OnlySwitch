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
        var id: String
        var stickerContent = ""
        var isColorSelectorPresented = false
        var isHovering = false
        var stickerColor: StickerColor = .yellow
        var canTranslucent = false
        var previewMode = false
        var collaspeMode = false
        
        init(
            id: String = UUID().uuidString,
            stickerContent: String = "",
            stickerColor: StickerColor = .yellow,
            canTranslucent: Bool = false,
            previewMode: Bool = false,
            collaspeMode: Bool = false
        ) {
            self.id = id
            self.stickerContent = stickerContent
            self.stickerColor = stickerColor
            self.canTranslucent = canTranslucent
            self.previewMode = previewMode
        }
    }
    
    enum Action: BindableAction, Equatable {
        case loadContent
        case saveContent
        case showColorSelector
        case changeColor(StickerColor)
        case closeSticker
        case hover(Bool)
        case toggleTranslucent
        case togglePreviewMode
        case toggleCollapseMode
        case binding(BindingAction<State>)
    }
    
    @Dependency(\.stickerService) var stickerService
    
    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .loadContent:
                let sticker = stickerService.loadSticker()
                state.stickerContent = sticker.content
                state.stickerColor = sticker.color
                state.canTranslucent = sticker.translucent
                state.previewMode = sticker.previewMode
                return .none
                
            case .saveContent:
                stickerService.saveSticker(
                    state.stickerContent,
                    state.stickerColor,
                    state.canTranslucent,
                    state.previewMode
                )
                return .none
                
            case .showColorSelector:
                state.isColorSelectorPresented = true
                return .none
                
            case .changeColor(let color):
                state.stickerColor = color
                state.isColorSelectorPresented = false
                return .send(.saveContent)
                
            case .closeSticker:
                return .run { @MainActor send in
                    try? await TopStickerSwitch.shared.operateSwitch(isOn: false)
                    NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.topSticker)
                }
                
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
                
            case .binding:
                return .none
            }
        }
    }
}
