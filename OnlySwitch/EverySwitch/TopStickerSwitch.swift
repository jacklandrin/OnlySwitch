//
//  TopStickerSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/28.
//

import Foundation
import AppKit
import SwiftUI
import ComposableArchitecture
import Switches
import Combine

final class TopStickerSwitch: SwitchProvider {

    static let shared = TopStickerSwitch()

    var type: SwitchType = .topSticker

    var delegate: SwitchDelegate?

    private var windows: [StickerWindow] = []
    private var isWindowVisable = false

    private var cancellables: Set<AnyCancellable> = []
    
    @Shared(.oldStickers) var oldStickerData: Data?
    var currentStickers: [StickerModel] = []
    
    init() {
        @Shared(.stickerCache) var stickerCache: [StickerModel]?
        // Migration
        if let oldStickerData,
           let stickers = try? JSONDecoder().decode([StickerModel].self, from: oldStickerData) {
            let stickersWithId = stickers.map {
                StickerModel(
                    content: $0.content,
                    color: $0.color,
                    trancelucent: $0.trancelucent ?? false,
                    previewMode: $0.previewMode ?? false
                )
            }
            $stickerCache.withLock { $0 = stickersWithId }
            $oldStickerData.withLock { $0 = nil }
        }
        
        
        $stickerCache.publisher.sink { [weak self] stickers in
            guard let self else { return }
            let newStickers: [StickerModel] = stickers ?? []
            Task { @MainActor in
                self.modifyWindows(by: newStickers)
            }
        }
        .store(in: &cancellables)
    }
    
    @MainActor
    func currentStatus() async -> Bool {
        isWindowVisable
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        @Shared(.stickerCache) var stickerCache: [StickerModel]?
        if isOn {
            if stickerCache == nil || stickerCache?.count == 0 {
                $stickerCache.withLock { $0 = [StickerModel()] }
            }
            guard let stickerCache else {
                return
            }
            windows = stickerCache.map {
                showWindow(sticker: $0)
            }
            isWindowVisable = true
            currentStickers = stickerCache
        } else {
            for window in windows {
                window.close()
            }
            isWindowVisable = false
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    private static func createWindow(with frame: NSRect) -> StickerWindow {
        let window = StickerWindow(
            contentRect: frame,
            styleMask: [.resizable],
            backing: .buffered,
            defer: false,
            screen: .main
        )
        
        [window].forEach {
            $0.isMovable = true
            $0.collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
            $0.level = .mainMenu
            $0.ignoresMouseEvents = false
            $0.hasShadow = true
            $0.isReleasedWhenClosed = false
            $0.backgroundColor = .clear
        }
        window.delegate = window

        return window
    }
    
    private func showWindow(sticker: StickerModel) -> StickerWindow {
        let view = NSHostingView(
            rootView: StickerView(
                store: Store(initialState: .init(sticker: sticker)) {
                    StickerReducer()
                        ._printChanges()
                }
            )
        )
        let stickerWindow = Self.createWindow(with: .zero)
        let contenRect = stickerWindow.contentRect(forFrameRect: stickerWindow.frame)
        let stickerId: String = sticker.id ?? "stickerWindow"
        view.frame = contenRect
        stickerWindow.contentView = view
        stickerWindow.center()
        stickerWindow.makeKeyAndOrderFront(nil)
        stickerWindow.isMovableByWindowBackground = true
        stickerWindow.setFrameUsingName(stickerId)
        stickerWindow.setFrameAutosaveName(stickerId)
        stickerWindow.stickerId = stickerId
        return stickerWindow
    }
    
    private func modifyWindows(by newStickers: [StickerModel]) {
        let idFor: (StickerModel) -> String = { $0.id ?? "stickerWindow" }
        let newIds = Set(newStickers.map(idFor))
        let currentIds = Set(currentStickers.map(idFor))

        // If windows aren't visible, just keep our snapshot updated and exit.
        if !isWindowVisable {
            currentStickers = newStickers
            return
        }

        // Show windows for stickers that are new (present in newStickers but not in currentStickers).
        for sticker in newStickers where !currentIds.contains(idFor(sticker)) {
            let window = showWindow(sticker: sticker)
            windows.append(window)
        }

        // Close windows for stickers that were removed (present in currentStickers but not in newStickers).
        let removedIds = currentIds.subtracting(newIds)
        for removedId in removedIds {
            // Close any window(s) that match the removed sticker id.
            for window in windows.filter({ $0.stickerId == removedId }) {
                window.close()
            }
            // Remove closed windows from our tracking array.
            windows.removeAll { $0.stickerId == removedId }
        }
        
        if windows.count == 0 {
            isWindowVisable = false
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.topSticker)
        }
        // Update the snapshot of currently displayed stickers.
        currentStickers = newStickers
    }
}

class StickerWindow: NSWindow, NSWindowDelegate {
    var stickerId: String = "stickerWindow"
    
    override var canBecomeKey: Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
