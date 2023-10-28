//
//  StickerView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import SwiftUI
import ComposableArchitecture

@available(macOS 13.0, *)
struct StickerView: View {

    let store: StoreOf<StickerReducer>
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack (spacing: 0) {
                Color.yellow
                    .frame(height: 20)
                TextEditor(
                    text: viewStore.binding(
                        get: { $0.stickerContent },
                        send: { .editContent($0) }
                    )
                )
                .font(.system(size: 15))
                .frame(minWidth: 180, minHeight: 180)
                .scrollContentBackground(.hidden)
                .foregroundStyle(.black)
                .background(.clear)
                .padding(.top, 4)
            }
            .background(Color(nsColor: .stickerYellow))
            .task {
                viewStore.send(.loadContent)
            }
            .onChange(of: controlActiveState) { newValue in
                switch newValue {
                    case .key, .active:
                        break
                    case .inactive:
                        viewStore.send(.saveContent)
                    @unknown default:
                        break
                }
            }
        }
    }
}

@available(macOS 13.0, *)
#Preview {
    StickerView(
        store: Store(initialState: StickerReducer.State()) {
            StickerReducer()
        }
    )
}
