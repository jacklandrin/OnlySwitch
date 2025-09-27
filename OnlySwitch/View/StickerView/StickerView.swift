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
    
    @Perception.Bindable var store: StoreOf<StickerReducer>
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var contentSize: CGSize = .zero
    
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                VStack (spacing: 0) {
                    bar
                    if !store.collaspeMode {
                        contentView
                            .padding(.top, 5)
                    }
                }
                .background(Color(store.stickerColor.content))
                
                if store.isColorSelectorPresented {
                    VStack {
                        HStack {
                            Spacer()
                            ForEach(StickerColor.allCases, id:\.self) { color in
                                Button(action: {
                                    store.send(.changeColor(color), animation: .easeOut)
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
    
    @ViewBuilder
    private var contentView: some View {
        if store.previewMode {
            previewModeView
        } else {
            TextEditor(
                text: $store.stickerContent
            )
            .font(.system(size: 15))
            .frame(minWidth: 200, minHeight: 200)
            .scrollContentBackground(.hidden)
            .foregroundStyle(.black)
            .background(.clear)
        }
    }
    
    @ViewBuilder
    private var previewModeView: some View {
        ScrollView {
            Markdown(store.stickerContent)
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
    }
    
    private func isOpacity(canTranslucent: Bool, isHovering: Bool) -> Bool {
        canTranslucent && !isHovering
    }
    
    @ViewBuilder
    private var bar: some View {
        HStack {
            if store.isHovering {
                Button(action: {
                    store.send(.closeSticker)
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                .transition(.opacity)
            }
            
            ZStack {
                // Tap target area
                Rectangle()
                    .foregroundStyle(.clear)
                
                // Show first line of content when collapsed
                if store.collaspeMode {
                    Text(store.stickerContent.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                store.send(.toggleCollapseMode)
            }
            
            if store.isHovering {
                barButtons
            }
        }
        .background(
            Rectangle()
                .foregroundStyle(Color(nsColor: store.stickerColor.bar))
                .frame(height: 20)
        )
        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.2), radius: 3)
    }
    
    @ViewBuilder
    private var barButtons: some View {
        HStack {
            Button(action: {
                store.send(.togglePreviewMode, animation: .easeInOut)
            }) {
                Image(systemName: store.previewMode ? "eye" : "keyboard.badge.eye")
                    .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.previewMode ? "Edit".localized() : "Preview".localized())
            .isHidden(store.collaspeMode, remove: true)
            
            Button(action: {
                store.send(.toggleTranslucent, animation: .easeInOut)
            }) {
                Image(store.canTranslucent ? "fill" : "translucent")
                    .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Translucent".localized())
            .isHidden(store.collaspeMode, remove: true)
            
            Button(action: {
                store.send(.showColorSelector, animation: .easeInOut)
            }) {
                Image(systemName: "paintpalette")
                    .fontWeight(.bold)
                    .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Color".localized())
            
            Button {
                store.send(.addSticker)
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                    .foregroundStyle(Color(nsColor: store.stickerColor.stroke))
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

@available(macOS 13.0, *)
#Preview {
    StickerView(
        store: Store(initialState: .init(sticker: StickerModel())) {
            StickerReducer()
        }
    )
}
