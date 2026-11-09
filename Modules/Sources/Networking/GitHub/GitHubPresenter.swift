//
//  GitHubPresenter.swift
//  Modules
//
//  Created by Jacklandrin on 2021/12/21.
//

import Alamofire
import Combine
import Foundation
import OSLog

private let gitHubLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch", category: "Network")

public final class GitHubPresenter: ObservableObject, GitHubRepositoryProtocol, @unchecked Sendable {
    public static let shared = GitHubPresenter()

    @Published private var state = GitHubReleaseState()
    private let remoteDataSource = GitHubRemoteDataSource()
    public var session = URLSession.shared

    public init() {}

    public var latestVersion: String {
        state.latestVersion
    }

    public var downloadURL: String {
        state.downloadURL
    }

    public var isTheNewestVersion: Bool {
        state.isTheNewestVersion
    }

    public var downloadCount: Int {
        state.downloadCount
    }

    public var updateHistoryInfo: String {
        state.updateHistoryInfo
    }

    public var updateHistoryList: [String] {
        state.updateHistoryList
    }

    public var myAppPath: String? {
        Self.appPath
    }

    public func checkUpdate<Release: GitHubReleaseLike>(releaseType: Release.Type, complete: @escaping (Result<Void, Error>) -> Void) {
        remoteDataSource.latestRelease(releaseType) { result in
            switch result {
                case let .success(latestRelease):
                    do {
                        try self.state.analyzeLastRelease(model: latestRelease)
                        complete(.success(()))
                    } catch {
                        complete(.failure(error))
                    }
                case let .failure(error):
                    complete(.failure(error))
            }
        }
    }

    public func requestReleases<Release: GitHubReleaseLike>(releaseType: Release.Type, complete: @escaping (Result<Void, Error>) -> Void) {
        remoteDataSource.releases(releaseType) { result in
            switch result {
                case let .success(releases):
                    self.state.analyzeReleases(models: releases)
                    complete(.success(()))
                case let .failure(error):
                    complete(.failure(error))
            }
        }
    }

    public func downloadDMG(complete: @escaping (Result<String, Error>) -> Void) {
        guard let basePath = Self.appPath else {
            complete(.failure(RequestError.invalidURL))
            return
        }
        let filePath = (basePath as NSString).appendingPathComponent("OnlySwitch.dmg")
        let destination: DownloadRequest.Destination = { _, _ in
            (URL(fileURLWithPath: filePath), [.removePreviousFile, .createIntermediateDirectories])
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

    public func requestShortcutsJson<T: Decodable>(type: T.Type, complete: @escaping (Result<T, Error>) -> Void) {
        remoteDataSource.shortcuts(type, complete: complete)
    }

    public func requestEvolutionJson<T: Decodable>(type: T.Type) async throws -> T {
        try await remoteDataSource.evolution(type)
    }

    public func downloadFile(from url: URL, to destination: URL) async throws {
        let (localURL, _) = try await session.download(from: url)
        do {
            let folderURL = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folderURL.path) {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
            try FileManager.default.moveItem(at: localURL, to: destination)
        } catch {
            gitHubLogger.error("\(error.localizedDescription)")
        }
    }

    public func downloadFile(from url: URL, name: String) async throws -> String {
        guard let basePath = Self.appPath else {
            throw RequestError.invalidURL
        }
        let destination = (basePath as NSString).appendingPathComponent(name)
        try await downloadFile(from: url, to: URL(fileURLWithPath: destination))
        return destination
    }
}

private extension GitHubPresenter {
    static var appPath: String? {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "OnlySwitch"
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).map(\.path)
        guard let directory = paths.first else { return nil }
        return (directory as NSString).appendingPathComponent(appBundleID)
    }
}
