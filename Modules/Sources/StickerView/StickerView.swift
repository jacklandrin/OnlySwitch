//
//  StickerView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import ComposableArchitecture
import SwiftUI

public struct StickerView: View {
    
    @SwiftUI.Bindable var store: StoreOf<StickerReducer>
    @Environment(\.controlActiveState) private var controlActiveState

    public init(store: StoreOf<StickerReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                VStack (spacing: 0) {
                    StickerBarView(store: store)
                    if !store.collaspeMode {
                        StickerContentView(store: store)
                            .padding(.top, 5)
                    }
                }
                .background(Color(store.stickerColor.content))
                
                if store.isColorSelectorPresented {
                    StickerColorSelectorView(store: store)
                }
            }
            .opacity(isOpacity(canTranslucent: store.canTranslucent, isHovering: store.isHovering) ? 0.6 : 1.0)
            .onHover { isHovering in
                store.send(.hover(isHovering))
            }
            .onChange(of: controlActiveState) { newValue in
                switch newValue {
                case .key, .active:
                    break
                case .inactive:
                    store.send(.saveContent)
                @unknown default:
                    break
                }
            }
        }
    }

    private func isOpacity(canTranslucent: Bool, isHovering: Bool) -> Bool {
        canTranslucent && !isHovering
    }
}

#Preview {
    StickerView(
        store: Store(initialState: .init(sticker: StickerModel())) {
            StickerReducer()
        }
    )
}
