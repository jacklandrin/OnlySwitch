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
            ZStack {
                VStack (spacing: 0) {
                    HStack {
                        if viewStore.isHovering {
                            Button(action: {
                                viewStore.send(.closeSticker)
                            }) {
                                Image(systemName: "xmark")
                                        .foregroundStyle(Color(nsColor: viewStore.stickerColor.stroke))
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 5)
                            .transition(.opacity)
                        }

                        Spacer()
                            .frame(height: 20)

                        if viewStore.isHovering {
                            Button(action: {
                                viewStore.send(.showColorSelector, animation: .easeInOut)
                            }) {
                                Image(systemName: "ellipsis")
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color(nsColor: viewStore.stickerColor.stroke))
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 5)
                            .transition(.opacity)
                        }
                    }
                    .background(
                        Rectangle()
                            .foregroundStyle(Color(nsColor: viewStore.stickerColor.bar))
                            .frame(height: 20)
                    )
                    .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.2), radius: 3)

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
                    .padding(.top, 5)
                }
                .background(Color(nsColor: viewStore.stickerColor.content))

                if viewStore.isColorSelectorPresented {
                    VStack {
                        HStack {
                            Spacer()
                            ForEach(StickerColor.allCases, id:\.self) { color in
                                Button(action: {
                                    viewStore.send(.changeColor(color), animation: .easeOut)
                                }) {
                                    Circle()
                                        .strokeBorder(Color(nsColor: color.stroke).opacity(0.5), lineWidth: 1)
                                        .background(Circle().foregroundColor(Color(nsColor: color.bar)))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 16, height: 16)
                                .padding(.top, 4)
                            }
                            Spacer()
                        }
                        .background(
                            Color.white
                                .frame(height: 24)
                        )
                        Spacer()
                    }
                    .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.2), radius: 1)
                    .transition(.move(edge: .top))
                }
            }
            .onHover { isHovering in
                viewStore.send(.hover(isHovering), animation: .easeInOut)
            }
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
