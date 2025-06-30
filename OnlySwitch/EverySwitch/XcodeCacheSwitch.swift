//
//  XcodeCacheSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import Foundation
import AppKit
import Switches

final class XcodeCacheSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .xcodeCache

    
    let derivedData = "Library/Developer/Xcode/DerivedData/"
    let xcodepath = "Library/Developer/Xcode/"
    
    var currentSize: Int {
        var size:Int = 0
        do {
            size = try derivedDataURL.directoryTotalAllocatedSize(includingSubfolders: true) ?? 0
        } catch {
            size = 0
        }
        return size
    }
    
    var lastSizeBeforeCleaning: Int? = 0
    var progressPercent: Double {
        let value = 1.0 - Double(currentSize) / Double(lastSizeBeforeCleaning ?? 1)
        print("clean progress:\(value) \(currentSize) \(lastSizeBeforeCleaning ?? 1)")
        return value
    }
    
    private let manager = FileManager.default
    
    private var derivedDataURL: URL {
        let home = manager.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(derivedData)
        return url
    }

    func currentStatus() async -> Bool {
        return true
    }

    func currentInfo() async -> String {
        do {
            return try derivedDataURL.sizeOnDisk() ?? ""
        } catch {
            return ""
        }
    }

    
    func isVisible() -> Bool {
        let home = manager.homeDirectoryForCurrentUser
        let xcodeURL = home.appendingPathComponent(xcodepath)
        let path = xcodeURL.absoluteString.replacingOccurrences(of: "file://", with: "")
        let exist = directoryExistsAtPath(path)
        return exist
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        let home = manager.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(derivedData)
        do {
            if isOn {
                lastSizeBeforeCleaning = try derivedDataURL.directoryTotalAllocatedSize(includingSubfolders: true)
                try manager.removeItem(at: url)
            }
        } catch {
            throw error
        }
    }
}
