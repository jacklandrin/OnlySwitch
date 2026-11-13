import Dependencies
import Extensions
import Foundation

public struct BrowserStoredState: Codable, Equatable, Sendable {
    public var bookmarks: [BrowserBookmark]
    public var selectedID: UUID?

    public init(bookmarks: [BrowserBookmark] = [], selectedID: UUID? = nil) {
        self.bookmarks = bookmarks
        self.selectedID = selectedID
    }
}

public enum BrowserLoadResult: Equatable, Sendable {
    case loaded(BrowserStoredState)
    /// The stored value could not be decoded; it is left untouched until the user changes bookmarks.
    case corrupted
}

/// Persists bookmarks and the selected bookmark as JSON in `UserDefaults`.
public struct BrowserStorageClient: Sendable {
    public var load: @Sendable () -> BrowserLoadResult
    public var save: @Sendable (BrowserStoredState) throws -> Void

    public init(
        load: @escaping @Sendable () -> BrowserLoadResult,
        save: @escaping @Sendable (BrowserStoredState) throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    public static func userDefaults(_ defaults: UserDefaults, key: String = UserDefaults.Key.browserState) -> Self {
        // `UserDefaults` is documented as thread-safe but not declared `Sendable`.
        let defaults = UncheckedSendable(defaults)
        return Self(
            load: {
                guard let value = defaults.value.object(forKey: key) else { return .loaded(BrowserStoredState()) }
                guard let data = value as? Data,
                      let state = try? JSONDecoder().decode(BrowserStoredState.self, from: data) else { return .corrupted }
                return .loaded(state)
            },
            save: { state in
                defaults.value.set(try JSONEncoder().encode(state), forKey: key)
            }
        )
    }
}

extension BrowserStorageClient: DependencyKey {
    public static let liveValue = Self.userDefaults(.standard)
    public static let testValue = Self(
        load: unimplemented("BrowserStorageClient.load", placeholder: .loaded(BrowserStoredState())),
        save: unimplemented("BrowserStorageClient.save")
    )
}

public extension DependencyValues {
    var browserStorage: BrowserStorageClient {
        get { self[BrowserStorageClient.self] }
        set { self[BrowserStorageClient.self] = newValue }
    }
}
