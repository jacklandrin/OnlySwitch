//
//  WallpaperManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/14.
//

import AppKit

class WallpaperManager {
    enum WallpaperError:Error {
        case ExistsIgnoredFile
    }
    
    
    static let shared = WallpaperManager()
    
    private var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
    
    func clearCache() throws {
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
        
        try removeAllFile(url: processedUrl, ignore: currentNames)
        try removeAllFile(url: originalUrl, ignore: currentNames)
        
    }
    
    func cacheSize() -> Int {
        guard let myAppPath = myAppPath else {
            return 0
        }
        let processedPath = myAppPath.appendingPathComponent(string: "processed")
        let originalPath = myAppPath.appendingPathComponent(string: "original")
        let processedUrl = URL(fileURLWithPath: processedPath)
        let originalUrl = URL(fileURLWithPath: originalPath)
        
        var processedSize = 0
        var originalSize = 0
        var size = 0
        do {
            processedSize = try processedUrl.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
            originalSize = try originalUrl.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
            size = processedSize + originalSize
        } catch {
            size = 0
        }
        return size
    }
    
    private func removeAllFile(url:URL, ignore:[String]) throws {
        do {
            let fileUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .includesDirectoriesPostOrder)
            var containsIgnoring = false
            for fileUrl in fileUrls {
                if !ignore.contains(fileUrl.lastPathComponent) {
                    try FileManager.default.removeItem(at: fileUrl)
                } else {
                    containsIgnoring = true
                }
            }
            if containsIgnoring {
                throw WallpaperError.ExistsIgnoredFile
            }
        } catch {
            throw error
        }
    }
}
