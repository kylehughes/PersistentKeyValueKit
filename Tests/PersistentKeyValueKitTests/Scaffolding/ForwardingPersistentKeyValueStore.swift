//
//  ForwardingPersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation
import PersistentKeyValueKit

/// A test store that forwards every ``PersistentKeyValueStore`` requirement to ``base``, so a test double declares only
/// the requirements it overrides.
protocol ForwardingPersistentKeyValueStore: PersistentKeyValueStore {
    associatedtype Base: PersistentKeyValueStore

    /// The store that receives every requirement this store does not override.
    var base: Base { get }
}

// MARK: - Default Implementation

extension ForwardingPersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            try base.migrationEndpoint
        }
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        base.get(key)
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }
}
