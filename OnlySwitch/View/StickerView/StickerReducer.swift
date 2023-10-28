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
    }

    enum Action: Equatable {
        case loadContent
        case editContent(String)
        case saveContent
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .loadContent:
                    if let content = Preferences.shared.stickerContent.first {
                        state.stickerContent = content
                    }
                    return .none
                    
                case .editContent(let content):
                    state.stickerContent = content
                    return .none
                    
                case .saveContent:
                    let contentArray = [state.stickerContent]
                    Preferences.shared.stickerContent = contentArray
                    return .none
            }
        }
    }
}
