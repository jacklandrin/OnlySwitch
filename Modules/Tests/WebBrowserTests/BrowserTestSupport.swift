import ComposableArchitecture
import Foundation
@testable import WebBrowser

extension BrowserBookmark {
    /// `n` must be a single digit; it becomes the last character of the ID.
    static func fixture(_ n: Int, mobile: Bool = false) -> Self {
        Self(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
            title: "Site \(n)",
            url: URL(string: "https://site\(n).example")!,
            usesMobileUserAgent: mobile
        )
    }
}

/// Records every web client command as `"<verb> <last UUID digit>[ <arg>]"` and every save.
final class WebCommandLog: Sendable {
    let commands = LockIsolated<[String]>([])
    let saves = LockIsolated<[BrowserStoredState]>([])

    func client(events: AsyncStream<BrowserNavigationEvent> = AsyncStream { $0.finish() }) -> BrowserWebClient {
        let log = commands
        @Sendable func record(_ verb: String, _ id: UUID, _ argument: String? = nil) {
            let entry = [verb, String(id.uuidString.suffix(1)), argument].compactMap { $0 }.joined(separator: " ")
            log.withValue { $0.append(entry) }
        }
        return BrowserWebClient(
            events: { events },
            activate: { record("activate", $0.id) },
            load: { record("load", $0, $1.absoluteString) },
            goBack: { record("back", $0) },
            goForward: { record("forward", $0) },
            reload: { record("reload", $0) },
            stop: { record("stop", $0) },
            setMobileUserAgent: { record("mobile", $0, String($1)) },
            discard: { record("discard", $0) },
            clearWebsiteData: { log.withValue { $0.append("clear") } }
        )
    }

    func storage(_ initial: BrowserLoadResult) -> BrowserStorageClient {
        let saves = saves
        return BrowserStorageClient(load: { initial }, save: { state in saves.withValue { $0.append(state) } })
    }
}
