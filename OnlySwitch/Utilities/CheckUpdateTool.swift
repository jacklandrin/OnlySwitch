//
//  CheckUpdateTool.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation
import Alamofire
import SwiftUI

struct ReleaseAssets:Decodable {
    let id:Int
    let label:String?
    let state:String
    let created_at:String
    let content_type:String
    let url:String
    let node_id:String
    let size:Int
    let updated_at:String
    let browser_download_url:String
    let name:String
    let download_count:Int
    
    enum CodingKeys:String, CodingKey {
        case id
        case label
        case state
        case created_at
        case content_type
        case url
        case node_id
        case size
        case updated_at
        case browser_download_url
        case name
        case download_count
    }
}

struct LatestRelease:Decodable {
    let id:Int
    let draft:Bool
    let published_at:String
    let assets:[ReleaseAssets]
    let prerelease:Bool
    let created_at:String
    let zipball_url:String
    let url:String
    let node_id:String
    let body:String
    let target_commitish:String
    let tarball_url:String
    let assets_url:String
    let upload_url:String
    let tag_name:String
    let name:String
    
    enum CodingKeys:String, CodingKey {
        case id
        case draft
        case published_at
        case assets
        case prerelease
        case created_at
        case zipball_url
        case url
        case node_id
        case body
        case target_commitish
        case tarball_url
        case assets_url
        case upload_url
        case tag_name
        case name
    }
}

class CheckUpdateTool{
    static let shared = CheckUpdateTool()
    var latestVersion:String = ""
    var downloadURL:String = ""
    func checkupdate(complete:@escaping (_ success:Bool) -> Void) {
        let request = AF.request("https://api.github.com/repos/jacklandrin/OnlySwitch/releases/latest")
        request.responseDecodable(of:LatestRelease.self) { response in
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
    
    func isTheNewestVersion() -> Bool {
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
