//
//  CurrentScreen.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/3.
//

import Foundation
import AppKit

protocol CurrentScreen{
    func getScreenWithMouse() -> NSScreen?
    func getWallpaperPath() -> URL?
}

extension CurrentScreen {
    func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first { NSMouseInRect(mouseLocation, $0.frame, false) })
        return screenWithMouse
    }
    
    func getWallpaperPath() -> URL? {
        let workspace = NSWorkspace.shared
        guard let screen = getScreenWithMouse() else {return nil}
        guard let path = workspace.desktopImageURL(for: screen) else {return nil}
        return path
    }
}
