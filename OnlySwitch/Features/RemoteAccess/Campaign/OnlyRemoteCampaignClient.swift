import AppKit
import Dependencies
import Extensions
import Foundation

struct OnlyRemoteCampaignManifest: Codable, Equatable, Sendable {
    let date: String
    let file: String

    var isValid: Bool {
        let bytes = Array(date.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }), file == date + ".html" else { return false }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        let (year, month, day) = (parts[0], parts[1], parts[2])
        guard year > 0, (1...12).contains(month) else { return false }
        let leapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }
}

struct OnlyRemoteCampaignDocument: Equatable, Sendable {
    let manifest: OnlyRemoteCampaignManifest
    let html: String
}

struct OnlyRemoteCampaignClient: Sendable {
    var fetchLatest: @Sendable () async throws -> OnlyRemoteCampaignManifest
    var fetchHTML: @Sendable (OnlyRemoteCampaignManifest) async throws -> String
    var acknowledgedVersion: @Sendable () -> String?
    var markAcknowledged: @Sendable (String) async -> Void
    var showQRCode: @Sendable () async -> Void = {}
}

extension OnlyRemoteCampaignClient: DependencyKey {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/onlyremote/id6793657946")!

    static var liveValue: Self {
        Self(
            fetchLatest: {
                let data = try await OnlyRemoteCampaignLoader.fetch("latest.json", limit: 64 * 1024)
                let manifest = try JSONDecoder().decode(OnlyRemoteCampaignManifest.self, from: data)
                guard manifest.isValid else { throw OnlyRemoteCampaignLoader.Failure.invalidContent }
                return manifest
            },
            fetchHTML: { manifest in
                guard manifest.isValid else { throw OnlyRemoteCampaignLoader.Failure.invalidContent }
                let data = try await OnlyRemoteCampaignLoader.fetch(manifest.file, limit: 2 * 1024 * 1024)
                guard let html = String(data: data, encoding: .utf8),
                      html.range(of: "<html", options: .caseInsensitive) != nil,
                      html.range(of: "</html>", options: .caseInsensitive) != nil else {
                    throw OnlyRemoteCampaignLoader.Failure.invalidContent
                }
                return html
            },
            acknowledgedVersion: {
                UserDefaults.standard.string(forKey: UserDefaults.Key.onlySwitchLaunchCampaignAcknowledgedDate)
            },
            markAcknowledged: { date in
                UserDefaults.standard.set(date, forKey: UserDefaults.Key.onlySwitchLaunchCampaignAcknowledgedDate)
            },
            showQRCode: {
                await MainActor.run {
                    QRCodeWindowController.shared.show(url: QRCodeWindowController.onlyRemoteQRCodeURL)
                }
            }
        )
    }

    static var testValue: Self {
        Self(
            fetchLatest: { throw OnlyRemoteCampaignLoader.Failure.invalidContent },
            fetchHTML: { _ in throw OnlyRemoteCampaignLoader.Failure.invalidContent },
            acknowledgedVersion: { nil },
            markAcknowledged: { _ in }
        )
    }
}

private enum OnlyRemoteCampaignLoader {
    enum Failure: Error { case invalidResponse, invalidContent, oversized }

    private static let baseURL = URL(string: "https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/LaunchCampaign/")!
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration, delegate: CampaignRedirectPolicy(), delegateQueue: nil)
    }()

    static func fetch(_ file: String, limit: Int) async throws -> Data {
        let url = baseURL.appendingPathComponent(file)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode), response.url == url else {
            throw Failure.invalidResponse
        }
        guard response.expectedContentLength <= Int64(limit) else { throw Failure.oversized }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw Failure.oversized }
            data.append(byte)
        }
        guard !data.isEmpty else { throw Failure.invalidContent }
        return data
    }
}

private final class CampaignRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension DependencyValues {
    var onlyRemoteCampaign: OnlyRemoteCampaignClient {
        get { self[OnlyRemoteCampaignClient.self] }
        set { self[OnlyRemoteCampaignClient.self] = newValue }
    }
}
