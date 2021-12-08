//
//  XcodeCacheSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import Foundation
class XcodeCacheSwitch:SwitchProvider {
    static let shared = XcodeCacheSwitch()
    let derivedData = "Library/Developer/Xcode/DerivedData/"
    let xcodepath = "Library/Developer/Xcode/"
    
    var currentSize:Int {
        var size:Int = 0
        do {
            size = try derivedDataURL.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
        } catch {
            size = 0
        }
        return size
    }
    
    var lastSizeBeforeCleaning:Int? = 0
    var progressPercent:Double {
        let value = 1.0 - Double(currentSize) / Double(lastSizeBeforeCleaning ?? 1)
        print("clean progress:\(value) \(currentSize) \(lastSizeBeforeCleaning ?? 1)")
        return value
    }
    
    private let manager = FileManager.default
    
    private var derivedDataURL:URL {
        let home = manager.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(derivedData)
        return url
    }
    
    
    func currentStatus() -> Bool {
        var size:Int? = 0
        do {
            size = try derivedDataURL.directoryTotalAllocatedSize(includingSubfolders: true)
        } catch {
            return false
        }
        return size == 0
    }
    
    func currentStatusAsync() async -> Bool {
        return currentStatus()
    }
    
    func currentInfo() -> String {
        do {
            return try derivedDataURL.sizeOnDisk() ?? ""
        } catch {
            return ""
        }
    }
    
    func currentInfoAsync() async -> String {
        return currentInfo()
    }
    
    
    func isVisable() -> Bool {
        let home = manager.homeDirectoryForCurrentUser
        let xcodeURL = home.appendingPathComponent(xcodepath)
        let path = xcodeURL.absoluteString.replacingOccurrences(of: "file://", with: "")
        let exist = directoryExistsAtPath(path)
        return exist
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        let home = manager.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(derivedData)
        do {
            if isOn {
                lastSizeBeforeCleaning = try derivedDataURL.directoryTotalAllocatedSize(includingSubfolders: true)
                try manager.removeItem(at: url)
                return true
            }
        } catch {
            return false
        }
        return false
    }
    
    
}
