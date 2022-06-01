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
        guard let url = makeRequestURL(path: .latestRelease) else {
            complete(false)
            return
        }
        let request = AF.request(url)
        request.responseDecodable(of:GitHubRelease.self) { response in
            guard let latestRelease = response.value else {
                complete(false)
                return
            }
            complete(self.interactor.analyzeLastRelease(model: latestRelease))
        }
    }
    
    func requestReleases(complete:@escaping (_ success:Bool) -> Void) {
        guard let url = makeRequestURL(path: .releases) else {
            complete(false)
            return
        }
        let request = AF.request(url)
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
    
    func requestShortcutsJson(complete:@escaping (_ list:[ShortcutOnMarket]?) -> Void) {
        guard let url = makeRequestURL(host:.userContent, path: .shortcutsJson) else {
            complete(nil)
            return
        }
        let request = AF.request(url)
        request.responseDecodable(of:[ShortcutOnMarket].self) { response in
            guard let list = response.value else {
                complete(nil)
                return
            }
            complete(list)
        }
    }
    
    private var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
    
    private func makeRequestURL(host:URLHost = .gitHubAPI, path:EndPointKinds) -> URL? {
        var components = URLComponents()
        components.scheme = httpsScheme
        components.host = host.rawValue
        components.path = "/" + path.rawValue
        return components.url
    }
}
