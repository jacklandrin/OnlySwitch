//
//  SettingsWindow.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/24.
//

import Defines
import Foundation
import AppKit

@MainActor
class SettingsWindow: NSWindow, NSWindowDelegate {
    static var shared = SettingsWindow()
    var isShowing = false
    private var isInitialized = false

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        self.delegate = self
        self.contentMinSize = NSSize(
            width: Layout.settingWindowWidth,
            height: Layout.settingWindowHeight
        )
    }

    func receiveSettingWindowOperation() {
        NotificationCenter.default.addObserver(
            forName: .settingsWindowOpened,
            object: nil,
            queue: .main
        ) { [weak self] notify in
            let window = notify.object as? NSWindow
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let window {
                    if !self.isInitialized {
                        self.contentViewController = window.contentViewController
                        self.title = window.title
                        self.setFrame(window.frame, display: false)
                        self.isInitialized = true
                        self.makeKeyAndOrderFront(nil)

                        window.close()
                    } else {
                        if !self.isShowing {
                            self.show()
                        }
                        window.close()
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .settingsWindowClosed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isShowing = false
                NSApp.activate(ignoringOtherApps: false)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .toggleSplitSettingsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.contentViewController?
                    .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if isInitialized {
            makeKeyAndOrderFront(nil)
            makeKey()
        } else {
            if let url = URL(string: "onlyswitch://SettingsWindow") {
                if #available(macOS 13.3, *) {
                    if !isShowing {
                        NSWorkspace.shared.open(url)
                        isShowing = true
                        print("new setting window appears")
                    }
                    if let window = NSApp.windows.first(where: { $0.title == "Settings" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } else {
                    NSWorkspace.shared.open(url)
                    print("new setting window appears")
                }
            }
        }
        isShowing = true
        NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
    }

    func hide() {
        close()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose()
        return true
    }

    private func onClose() {
        print("settings window closing")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(self)
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
    }
}
