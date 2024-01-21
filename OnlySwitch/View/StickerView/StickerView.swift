//
//  StickerView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import ComposableArchitecture
import MarkdownUI
import SwiftUI

@available(macOS 13.0, *)
struct StickerView: View {

    let store: StoreOf<StickerReducer>
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ZStack {
                VStack (spacing: 0) {
                    bar
                    Group{
                        if viewStore.previewMode {
                            ScrollView {
                                Markdown(viewStore.stickerContent)
                                    .markdownTextStyle() {
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
                        } else {
                            TextEditor(
                                text: viewStore.binding(
                                    get: { $0.stickerContent },
                                    send: { .editContent($0) }
                                )
                            )
                            .font(.system(size: 15))
                            .frame(minWidth: 200, minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(.black)
                            .background(.clear)
                        }
                    }
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
            .opacity(isOpacity(canTranslucent: viewStore.canTranslucent, isHovering: viewStore.isHovering) ? 0.6 : 1.0)
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

    private func isOpacity(canTranslucent: Bool, isHovering: Bool) -> Bool {
        canTranslucent && !isHovering
    }

    private var bar: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
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
                    HStack {
                        Button(action: {
                            viewStore.send(.togglePreviewMode, animation: .easeInOut)
                        }) {
                            Image(systemName: viewStore.previewMode ? "eye" : "keyboard.badge.eye")
                                    .foregroundStyle(Color(nsColor: viewStore.stickerColor.stroke))
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(viewStore.previewMode ? "Edit".localized() : "Preview".localized())

                        Button(action: {
                            viewStore.send(.toggleTranslucent, animation: .easeInOut)
                        }) {
                            Image(viewStore.canTranslucent ? "fill" : "translucent")
                                    .foregroundStyle(Color(nsColor: viewStore.stickerColor.stroke))
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Translucent".localized())

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
                        .help("Color".localized())
                    }
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
