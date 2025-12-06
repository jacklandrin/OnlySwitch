//
//  KeychainStorageKey.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import Foundation
import Sharing

public struct KeychainStorageKey<StoredValue: Codable & Equatable & Sendable> {
    public struct Default: SharedKey, Equatable, Hashable {
        public func save(_ value: StoredValue, context: Sharing.SaveContext, continuation: Sharing.SaveContinuation) {
            do {
                let data = try JSONEncoder().encode(value)
                guard let stringValue = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: KeychainError.unexpectedData)
                    return
                }
                try keychainManager.save(key: key, value: stringValue)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
        public func load(context: Sharing.LoadContext<StoredValue>, continuation: Sharing.LoadContinuation<StoredValue>) {
            do {
                if let stringValue = try keychainManager.retrieve(key: key),
                   let data = stringValue.data(using: .utf8),
                   let value = try? JSONDecoder().decode(StoredValue.self, from: data) {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: defaultValue)
                }
            } catch {
                continuation.resume(returning: defaultValue)
            }
        }
        
        public func subscribe(context: Sharing.LoadContext<StoredValue>, subscriber: Sharing.SharedSubscriber<StoredValue>) -> Sharing.SharedSubscription {
            // Keychain doesn't support real-time updates, so we just send the current value once
            Task {
                let current: StoredValue
                if let stringValue = try? keychainManager.retrieve(key: key),
                   let data = stringValue.data(using: .utf8),
                   let value = try? JSONDecoder().decode(StoredValue.self, from: data) {
                    current = value
                } else {
                    current = defaultValue
                }
                // SharedSubscriber in our Sharing module is a simple value consumer.
                // Use its `yield(_:)` method to deliver a single value.
                subscriber.yield(current)
            }
            // Return a no-op subscription since Keychain doesn't support change notifications
            return SharedSubscription { }
        }
        
        public typealias Value = StoredValue
        
        
        public let key: String
        public let defaultValue: StoredValue
        private let service: String
        
        public init(key: String, defaultValue: StoredValue, service: String) {
            self.key = key
            self.defaultValue = defaultValue
            self.service = service
        }
        
        private var keychainManager: KeychainManager {
            KeychainManager(service: service)
        }
        
        public static func == (lhs: Default, rhs: Default) -> Bool {
            lhs.key == rhs.key && lhs.service == rhs.service
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(service)
        }
    }
}

extension SharedKey where Self == KeychainStorageKey<String>.Default {
    public static func keychainStorage(
        key: String,
        defaultValue: String = "",
        service: String
    ) -> Self {
        Self(key: key, defaultValue: defaultValue, service: service)
    }
}

