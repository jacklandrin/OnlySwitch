//
//  GitHubInteractor.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/24.
//

import Foundation

class GitHubInteractor {
    var latestVersion:String = ""
    var downloadURL:String = ""
    var downloadCount:Int = 0
    var isTheNewestVersion: Bool {
        let currentVersion = SystemInfo.majorVersion as! String
        let currentVersionSplited = currentVersion.split(separator: ".")
        let latestVersionSplited = latestVersion.split(separator: ".")
        for index in 0..<(min(currentVersionSplited.count, latestVersionSplited.count)) {
            let currentNumber = Int(currentVersionSplited[index])!
            let latestNumber = Int(latestVersionSplited[index])!
            if latestNumber > currentNumber {
                return false
            }
        }
        if latestVersionSplited.count > currentVersionSplited.count { //for example: 1.4.1 vs 1.4
            return false
        }
        return true
    }
    var updateHistoryInfo:String = ""
    
    func analyzeLastRelease(model:GitHubRelease) throws {
        self.latestVersion = model.name.replacingOccurrences(of: "release_", with: "")
        if let asset = model.assets.first {
            self.downloadURL = asset.browser_download_url
        } else {
            throw RequestError.analyseModelFailed
        }
    }
    
    func analyzeReleases(models:[GitHubRelease]) {
        var count:Int = 0
        var updateInfo:String = ""
        for release in models {
            if let assert = release.assets.first {
                count += assert.download_count
            }
            updateInfo += "\(release.name):\r\n\(release.body)\r\n---------------------------------\r\n"
        }
        self.downloadCount = count
        self.updateHistoryInfo = updateInfo
    }
}
