//
//  CheckUpdateTool.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation
import Alamofire
import SwiftUI


class GitHubPresenter: GitHubRepositoryProtocol{
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
    
    func checkUpdate(complete:@escaping (Result<Void,Error>) -> Void) {
        guard let url = makeRequestURL(path: .latestRelease) else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        let request = AF.request(url)
        request.responseDecodable(of:GitHubRelease.self) { response in
            guard let latestRelease = response.value else {
                complete(.failure(RequestError.failed))
                return
            }
            do {
                try self.interactor.analyzeLastRelease(model: latestRelease)
                complete(.success(()))
            } catch {
                complete(.failure(error))
            }
        }
    }
    
    func requestReleases(complete:@escaping (Result<Void,Error>) -> Void) {
        guard let url = makeRequestURL(path: .releases) else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        let request = AF.request(url)
        request.responseDecodable(of:[GitHubRelease].self) { response in
            guard let releases = response.value else {
                complete(.failure(RequestError.failed))
                return
            }
            self.interactor.analyzeReleases(models: releases)
            complete(.success(()))
        }
    }
    
    func downloadDMG(complete:@escaping (Result<String,Error>) -> Void ) {
        let filePath = myAppPath?.appendingPathComponent(string: "OnlySwitch.dmg")
        guard let filePath = filePath else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        let destination: DownloadRequest.Destination = { _, _ in
            return (URL(fileURLWithPath: filePath), [.removePreviousFile, .createIntermediateDirectories])
        }

        let request = AF.download(downloadURL, to: destination)
        request.response { response in
            if response.error == nil, let path = response.fileURL?.path {
                complete(.success(path))
            } else {
                complete(.failure(RequestError.failed))
            }
        }
    }
    
    func requestShortcutsJson(complete:@escaping (Result<[ShortcutOnMarket], Error>) -> Void) {
        guard let url = makeRequestURL(host:.userContent, path: .shortcutsJson) else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        let request = AF.request(url)
        request.responseDecodable(of:[ShortcutOnMarket].self) { response in
            guard let list = response.value else {
                complete(.failure(RequestError.failed))
                return
            }
            complete(.success(list))
        }
    }
    
    
}
