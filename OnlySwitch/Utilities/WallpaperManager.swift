//
//  WallpaperManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import AppKit

class WallpaperManager {
    static let shared = WallpaperManager()
    
    private var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
    
    func clearCache() {
        guard let myAppPath = myAppPath else {
            return
        }

        let processedPath = myAppPath.appendingPathComponent(string: "processed")
        let originalPath = myAppPath.appendingPathComponent(string: "original")
        var currentNames = [String]()
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            if let path = workspace.desktopImageURL(for: screen){
                currentNames.append(path.lastPathComponent)
            }
        }
        
        let processedUrl = URL(fileURLWithPath: processedPath)
        let originalUrl = URL(fileURLWithPath: originalPath)
        
        removeAllFile(url: processedUrl, ignore: currentNames)
        removeAllFile(url: originalUrl, ignore: currentNames)
        
    }
    
    func cacheSize() -> String {
        guard let myAppPath = myAppPath else {
            return ""
        }
        let processedPath = myAppPath.appendingPathComponent(string: "processed")
        let originalPath = myAppPath.appendingPathComponent(string: "original")
        let processedUrl = URL(fileURLWithPath: processedPath)
        let originalUrl = URL(fileURLWithPath: originalPath)
        
        var processedSize = 0
        var originalSize = 0
        var size = ""
        do {
            processedSize = try processedUrl.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
            originalSize = try originalUrl.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
            URL.byteCountFormatter.countStyle = .file
            guard let byteCount = URL.byteCountFormatter.string(for: processedSize + originalSize) else { return ""}
            size = byteCount
        } catch {
            size = ""
        }
        return size
    }
    
    private func removeAllFile(url:URL, ignore:[String]) {
        do {
            let fileUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for fileUrl in fileUrls {
                if !ignore.contains(fileUrl.lastPathComponent) {
                    try FileManager.default.removeItem(at: fileUrl)
                }
            }
        } catch {
            
        }
    }
}
