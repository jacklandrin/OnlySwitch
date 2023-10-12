//
//  GithubRepositoryProtocol.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/4.
//

import Foundation

protocol GitHubRepositoryProtocol {
    var latestVersion:String {get}
    var downloadURL:String {get}
    var isTheNewestVersion: Bool {get}
    var downloadCount:Int {get}
    var updateHistoryInfo:String {get}
    
    func checkUpdate(complete:@escaping (Result<Void, Error>) -> Void)
    func requestReleases(complete:@escaping (Result<Void, Error>) -> Void)
    func downloadDMG(complete:@escaping (Result<String, Error>) -> Void)
    func requestShortcutsJson(complete:@escaping (Result<[ShortcutOnMarket], Error>) -> Void)
    func requestEvolutionJson() async throws -> [EvolutionGalleryModel]
}

extension GitHubRepositoryProtocol {
    var myAppPath:String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        let directory = paths.first
        let myAppPath = directory?.appendingPathComponent(string: appBundleID)
        return myAppPath
    }
    
    func makeRequestURL(host:URLHost = .gitHubAPI, path:EndPointKinds) -> URL? {
        var components = URLComponents()
        components.scheme = httpsScheme
        components.host = host.rawValue
        components.path = "/" + path.rawValue
        return components.url
    }

    func decode<T: Decodable>(data: Data?, type: T.Type) throws -> T {
        guard
            let data,
            !data.isEmpty
        else {
            throw RequestError.analyseModelFailed
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RequestError.analyseModelFailed
        }
    }
}
