//
//  CheckUpdateTool.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation
import Alamofire
import SwiftUI

let newestVersionKey = "newestVersionKey"

class CheckUpdatePresenter{
    var latestVersion:String = ""
    var downloadURL:String = ""
    
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
    
    func checkUpdate(complete:@escaping (_ success:Bool) -> Void) {
        let request = AF.request("https://api.github.com/repos/jacklandrin/OnlySwitch/releases/latest")
        request.responseDecodable(of:GitHubRelease.self) { response in
            guard let latestRelease = response.value else {
                complete(false)
                return
            }
            self.latestVersion = latestRelease.name.replacingOccurrences(of: "release_", with: "")
            if let asset = latestRelease.assets.first {
                self.downloadURL = asset.browser_download_url
                complete(true)
            }
            complete(false)
        }
    }
    
    
    func downloadDMG(complete:@escaping (_ success:Bool, _ path:String?) -> Void ) {
        let filePath = myAppPath?.appendingPathComponent(string: "OnlySwitch.dmg")
        guard let filePath = filePath else {
            complete(false, nil)
            return
        }
        let destination: DownloadRequest.Destination = { _, _ in
            return (URL(fileURLWithPath: filePath), [.removePreviousFile, .createIntermediateDirectories])
        }

        let request = AF.download(downloadURL, to: destination)
        request.response { response in
            if response.error == nil, let path = response.fileURL?.path {
                complete(true, path)
            } else {
                complete(false, nil)
            }
        }
    }
    
    private var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
}
