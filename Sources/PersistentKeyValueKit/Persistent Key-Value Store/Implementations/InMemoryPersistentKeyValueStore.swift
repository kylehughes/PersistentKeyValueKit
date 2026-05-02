//
//  InMemoryPersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

/// A key-value store that persists data in memory.
///
/// This store is useful for testing and development purposes, although `UserDefaults.standard` often works just as
/// well.
///
/// There is nothing that prevents it from being used in production, but it may be a sign that you are using the library 
/// unnecessarily. The library is intended to be used exclusively as a general interface on top of the two persistent
/// key-value stores provided by Apple platforms: `UserDefaults` and `NSUbiquitousKeyValueStore`.
///
/// - Important: Storage access is protected by a lock so this type can satisfy
///   ``PersistentKeyValueStore``'s thread-safety requirement.
public final class InMemoryPersistentKeyValueStore: @unchecked Sendable {
    private let lock: NSLock
    private var observations: [Observation]
    private var storage: [String: Any]
    
    // MARK: Public Initialization
    
    /// Creates a new in-memory key-value store.
    public init() {
        lock = NSLock()
        observations = []
        storage = [:]
    }
    
    // MARK: Private Instance Interface

    @discardableResult
    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// MARK: - PersistentKeyValueStore Extension

extension InMemoryPersistentKeyValueStore: PersistentKeyValueStore {
    // MARK: Getting Values
    
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        let value = withLock {
            storage[key.id]
        }

        return value as? Key.Value ?? key.defaultValue
    }
    
    // MARK: Setting Values
    
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        let keyID = key.id
        let storedValue: Any

        // We loosely try to replicate property list behavior of not representing `nil` values in storage.
        if let array = value as? [Any?] {
            storedValue = array.compactMap(\.self)
        } else if let dict = value as? [String: Any?] {
            storedValue = dict.compactMapValues(\.self)
        } else {
            storedValue = value
        }

        let observations = withLock {
            storage[keyID] = storedValue

            return liveObservations(for: keyID)
        }

        notify(observations, keyPath: keyID)
    }
    
    // MARK: Removing Values
    
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        let keyID = key.id

        let observations = withLock {
            storage.removeValue(forKey: keyID)

            return liveObservations(for: keyID)
        }

        notify(observations, keyPath: keyID)
    }
    
    // MARK: Observing Keys
    
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        let keyID = key.id

        withLock {
            observations.removeAll { observation in
                guard let registeredObserver = observation.observer else {
                    return true
                }

                return registeredObserver === observer && observation.keyID == keyID && observation.context == context
            }
        }
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let keyID = key.id

        withLock {
            observations.removeAll { $0.observer == nil }
            observations.append(
                Observation(
                    observer: target,
                    keyID: keyID,
                    context: context
                )
            )
        }
    }

    private func liveObservations(for keyID: String) -> [Observation] {
        observations.removeAll { $0.observer == nil }

        return observations.filter {
            $0.keyID == keyID
        }
    }

    private func notify(_ observations: [Observation], keyPath: String?) {
        for observation in observations {
            observation.observer?.observeValue(
                forKeyPath: keyPath,
                of: self,
                change: nil,
                context: observation.context
            )
        }
    }
}

// MARK: - Observation Definition

extension InMemoryPersistentKeyValueStore {
    private struct Observation {
        weak var observer: NSObject?
        let keyID: String
        let context: UnsafeMutableRawPointer?
    }
}

// MARK: - Static Accessors

extension PersistentKeyValueStore where Self == InMemoryPersistentKeyValueStore {
    // MARK: Public Static Interface
    
    /// A store suitable for use in development, e.g. SwiftUI previews.
    @inlinable
    public static var ephemeral: Self {
        InMemoryPersistentKeyValueStore()
    }
}
