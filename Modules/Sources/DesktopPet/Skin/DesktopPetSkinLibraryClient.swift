import ComposableArchitecture
import DesktopPetSkinKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jacklandrin.OnlySwitch", category: "DesktopPetSkinLibrary")

public enum DesktopPetSkinLibraryError: Error, Equatable, Sendable { case full }

public struct DesktopPetSkinLibraryClient: Sendable {
    public static let maximumSkins = 24
    public static let selectedIDKey = "desktopPetSkinIDKey"

    public var load: @Sendable () async -> [DesktopPetSkin]
    public var save: @Sendable (DesktopPetSkin) async throws -> [DesktopPetSkin]
    public var delete: @Sendable (UUID) async throws -> [DesktopPetSkin]
    public var selectedID: @Sendable () -> UUID?
    public var select: @Sendable (UUID?) -> Void

    public init(
        load: @escaping @Sendable () async -> [DesktopPetSkin] = { [] },
        save: @escaping @Sendable (DesktopPetSkin) async throws -> [DesktopPetSkin] = { _ in [] },
        delete: @escaping @Sendable (UUID) async throws -> [DesktopPetSkin] = { _ in [] },
        selectedID: @escaping @Sendable () -> UUID? = { nil },
        select: @escaping @Sendable (UUID?) -> Void = { _ in }
    ) {
        self.load = load; self.save = save; self.delete = delete
        self.selectedID = selectedID; self.select = select
    }

    public static func live(fileURL: URL, defaults: UserDefaults) -> Self {
        let store = DesktopPetSkinFileStore(fileURL: fileURL)
        let defaults = UncheckedSendable(defaults)
        let selectedID: @Sendable () -> UUID? = {
            defaults.value.string(forKey: selectedIDKey).flatMap(UUID.init(uuidString:))
        }
        let select: @Sendable (UUID?) -> Void = { id in
            defaults.value.set(id?.uuidString, forKey: selectedIDKey)
        }
        return Self(
            load: { await store.load() },
            save: { skin in try await store.upsert(skin) },
            delete: { id in
                let skins = try await store.remove(id)
                if selectedID() == id { select(nil) }
                return skins
            },
            selectedID: selectedID,
            select: select
        )
    }
}

/// Serializes file access so concurrent saves never interleave.
actor DesktopPetSkinFileStore {
    private let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() -> [DesktopPetSkin] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let skins = try? JSONDecoder().decode([DesktopPetSkin].self, from: data) else {
            logger.error("Desktop pet skin library is unreadable")
            return []
        }
        return skins.filter { skin in
            skin.contractVersion == DesktopPetSkinContract.version
                && (try? DesktopPetSkinValidator.validate(skin.markup)) != nil
        }
    }

    func upsert(_ skin: DesktopPetSkin) throws -> [DesktopPetSkin] {
        var skins = load()
        if let index = skins.firstIndex(where: { $0.id == skin.id }) {
            skins[index] = skin
        } else {
            guard skins.count < DesktopPetSkinLibraryClient.maximumSkins else { throw DesktopPetSkinLibraryError.full }
            skins.append(skin)
        }
        try write(skins)
        return skins
    }

    func remove(_ id: UUID) throws -> [DesktopPetSkin] {
        let skins = load().filter { $0.id != id }
        try write(skins)
        return skins
    }

    private func write(_ skins: [DesktopPetSkin]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(skins).write(to: fileURL, options: .atomic)
    }
}

extension DesktopPetSkinLibraryClient: DependencyKey {
    public static var liveValue: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier ?? "OnlySwitch"
        return .live(fileURL: support.appending(path: "\(folder)/DesktopPetSkins.json"), defaults: .standard)
    }
    public static let testValue = Self()
}

extension DependencyValues {
    public var desktopPetSkinLibrary: DesktopPetSkinLibraryClient {
        get { self[DesktopPetSkinLibraryClient.self] }
        set { self[DesktopPetSkinLibraryClient.self] = newValue }
    }
}
