//
//  GithubMockRespository.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/4.
//

import Foundation
@testable import OnlySwitch

class GitHubMockRespository:GitHubRepositoryProtocol {
    
    private var interactor = GitHubInteractor()
    private var bundle:Bundle {
        Bundle(for: type(of: self))
    }
    
    var latestVersion: String {
        return interactor.latestVersion
    }
    
    var downloadURL: String {
        return interactor.downloadURL
    }
    
    var isTheNewestVersion: Bool {
        return interactor.isTheNewestVersion
    }
    
    var downloadCount: Int {
        return interactor.downloadCount
    }
    
    var updateHistoryInfo: String {
        return interactor.updateHistoryInfo
    }
    
    func checkUpdate(complete: @escaping (Result<Void,Error>) -> Void) {
        guard let url = bundle.url(forResource: "Latest_release_mock", withExtension: "json") else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let latestRelease = try JSONDecoder().decode(GitHubRelease.self, from:data)
            try self.interactor.analyzeLastRelease(model: latestRelease)
            complete(.success(()))
        } catch {
            complete(.failure(RequestError.failed))
        }
    }
    
    func requestReleases(complete: @escaping (Result<Void,Error>) -> Void) {
        
        guard let url = bundle.url(forResource: "Releases_mock", withExtension: "json") else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            self.interactor.analyzeReleases(models: releases)
            complete(.success(()))
        } catch {
            complete(.failure(RequestError.failed))
        }
    }
    
    func downloadDMG(complete: @escaping (Result<String, Error>) -> Void) {
        
    }
    
    func requestShortcutsJson(complete: @escaping (Result<[ShortcutOnMarket], Error>) -> Void) {
        guard let url = bundle.url(forResource: "ShortcutsMarket", withExtension: "json") else {
            complete(.failure(RequestError.invalidURL))
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let allShortcutsOnMarket = try JSONDecoder().decode([ShortcutOnMarket].self, from: data)
            complete(.success(allShortcutsOnMarket))
        } catch {
            complete(.failure(RequestError.failed))
        }
    }
    
    func requestEvolutionJson() async throws -> [OnlySwitch.EvolutionGalleryModel] {
        // TODO: Not used. Just to silence Xcode
        return []
    }
}
