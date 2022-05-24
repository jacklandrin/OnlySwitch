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

class GitHubPresenter{
    private let interactor = GitHubInteractor()
    
    var latestVersion:String {
        return interactor.latestVersion
    }
    
    var downloadURL:String {
        return interactor.downloadURL
    }
    
    var isTheNewestVersion: Bool {
        return interactor.isTheNewestVersion
    }
    
    var downloadCount:Int {
        return interactor.downloadCount
    }
    
    var updateHistoryInfo:String {
        return interactor.updateHistoryInfo
    }
    
    func checkUpdate(complete:@escaping (_ success:Bool) -> Void) {
        let request = AF.request("https://api.github.com/repos/jacklandrin/OnlySwitch/releases/latest")
        request.responseDecodable(of:GitHubRelease.self) { response in
            guard let latestRelease = response.value else {
                complete(false)
                return
            }
            complete(self.interactor.analyzeLastRelease(model: latestRelease))
        }
    }
    
    func requestReleases(complete:@escaping (_ success:Bool) -> Void) {
        let request = AF.request("https://api.github.com/repos/jacklandrin/OnlySwitch/releases")
        request.responseDecodable(of:[GitHubRelease].self) { response in
            guard let releases = response.value else {
                complete(false)
                return
            }
            self.interactor.analyzeReleases(models: releases)
            complete(true)
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
