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

final class TopStickerSwitch: SwitchProvider {

    static let shared = TopStickerSwitch()

    var type: SwitchType = .topSticker

    var delegate: SwitchDelegate?

    private var window: StickerWindow?
    private var isWindowVisable = false

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
        if #available(macOS 13.0, *) {
            if isOn {
                if window == nil {
                    
                    let view = NSHostingView(
                        rootView: StickerView(
                            store: Store(initialState: StickerReducer.State()) {
                                StickerReducer()
                                    ._printChanges()
                            }
                        )
                    )
                    let stickerWindow = Self.createWindow(with: .zero)
                    let contenRect = stickerWindow.contentRect(forFrameRect: stickerWindow.frame)
                    view.frame = contenRect
                    stickerWindow.contentView = view
                    stickerWindow.center()
                    window = stickerWindow
                }
                window?.makeKeyAndOrderFront(nil)
                window?.isMovableByWindowBackground = true
                window?.setFrameUsingName("StickerWindow")
                window?.setFrameAutosaveName("StickerWindow")
                isWindowVisable = true
            } else {
                window?.close()
                isWindowVisable = false
            }
        }
    }
    
    func isVisible() -> Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
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

        return window
    }
}

class StickerWindow: NSWindow, NSWindowDelegate {
    override var canBecomeKey: Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
