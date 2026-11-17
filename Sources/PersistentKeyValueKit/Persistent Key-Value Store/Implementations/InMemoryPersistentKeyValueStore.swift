//
//  InMemoryPersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

/// A thread-safe key-value store that keeps values in memory for the lifetime of the instance.
///
/// Use `InMemoryPersistentKeyValueStore` for unit tests, SwiftUI previews, and ephemeral storage without touching
/// `UserDefaults` or `NSUbiquitousKeyValueStore`.
///
/// Unlike Foundation stores, `InMemoryPersistentKeyValueStore` stores typed Swift values directly (compacting `nil`
/// elements out of arrays and dictionaries of optionals) and records an explicit entry when an optional key is set to
/// `nil`. Calling ``remove(_:)`` deletes the entry. When migrating a stored `nil` from an in-memory store to
/// `UserDefaults` or `NSUbiquitousKeyValueStore` with
/// ``PersistentKeyCopyConflictPolicy/overwriteDestination`` or
/// ``PersistentKeyMoveConflictPolicy/overwriteDestination``, the destination key is removed.
///
/// - Important: Storage access is protected by a lock so this type satisfies ``PersistentKeyValueStore``'s
///   thread-safety requirement.
public final class InMemoryPersistentKeyValueStore: @unchecked Sendable {
    /// The stable identity of this in-memory store for migration operations.
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity

    private let lock: NSLock
    private var nextRevision: UInt64
    private var observations: [Observation]
    private var storage: [String: StoredValue]

    // MARK: Public Initialization

    /// Creates a new in-memory key-value store.
    public init() {
        lock = NSLock()
        observations = []
        storage = [:]
        nextRevision = 0
        migrationIdentity = PersistentKeyValueMigrationStoreIdentity(
            namespace: "InMemoryPersistentKeyValueStore",
            identifier: UUID().uuidString
        )
    }

    // MARK: Private Static Interface

    private static func normalizedValue<T>(_ value: T) -> Any {
        if let array = value as? [Any?] {
            return array.compactMap(\.self)
        }

        if let dictionary = value as? [String: Any?] {
            return dictionary.compactMapValues(\.self)
        }

        return value
    }

    // MARK: Private Instance Interface

    private func liveObservations(for keyID: String) -> [Observation] {
        observations.removeAll {
            $0.observer == nil
        }

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

    @discardableResult
    private func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return try body()
    }
}

// MARK: - Migration Backend Extension

extension InMemoryPersistentKeyValueStore: PersistentKeyValueMigrationBackend {
    // MARK: Internal Instance Interface

    /// Commits a prepared write only when the replacement snapshot is still current.
    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        let result: (MigrationSnapshot, [Observation]) = try withLock {
            guard write.identity == migrationIdentity else {
                throw PersistentKeyMigrationError.invalidSnapshot
            }

            if let snapshot, snapshot.identity != migrationIdentity || snapshot.keyID != write.keyID {
                throw PersistentKeyMigrationError.invalidSnapshot
            }

            if let snapshot, storage[write.keyID]?.revision != snapshot.revision {
                throw PersistentKeyMigrationError.destinationChanged
            }

            if snapshot == nil, storage[write.keyID] != nil {
                throw PersistentKeyMigrationError.destinationChanged
            }

            nextRevision &+= 1
            storage[write.keyID] = StoredValue(object: write.object, revision: nextRevision)
            let committed = MigrationSnapshot(
                identity: migrationIdentity,
                keyID: write.keyID,
                revision: nextRevision,
                object: write.object
            )
            return (committed, liveObservations(for: write.keyID))
        }

        notify(result.1, keyPath: write.keyID)
        guard try migrationSnapshotIsCurrent(result.0, for: write.keyID) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return result.0
    }

    /// Captures the persisted value and revision for a key, or `nil` when the key is absent.
    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        withLock {
            guard let storedValue = storage[keyID] else {
                return nil
            }

            return MigrationSnapshot(
                identity: migrationIdentity,
                keyID: keyID,
                revision: storedValue.revision,
                object: storedValue.object
            )
        }
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }

        return withLock {
            storage[keyID]?.revision == snapshot.revision
        }
    }

    /// Decodes a captured value for the requested typed key.
    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == key.id else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }

        let object = snapshot.object
        guard let value = object as? Key.Value else {
            throw PersistentKeyValueConversionError.invalidValue
        }

        return value
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        let object = Self.normalizedValue(value)
        guard object is Key.Value else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: object)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }

        let observations = try withLock {
            () -> [Observation] in
            guard storage[keyID]?.revision == snapshot.revision else {
                throw PersistentKeyMigrationError.sourceChanged
            }

            storage.removeValue(forKey: keyID)
            return liveObservations(for: keyID)
        }

        notify(observations, keyPath: keyID)
        guard try migrationSnapshot(for: keyID) == nil else {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }
    }
}

// MARK: - PersistentKeyValueStore Extension

extension InMemoryPersistentKeyValueStore: PersistentKeyValueStore {
    /// The migration capability for this in-memory store.
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        PersistentKeyValueMigrationEndpoint(backend: self)
    }

    // MARK: Getting Values

    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        let value = withLock {
            storage[key.id]?.object
        }

        return value as? Key.Value ?? key.defaultValue
    }

    // MARK: Setting Values

    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        let keyID = key.id
        let storedValue = Self.normalizedValue(value)

        let observations = withLock {
            nextRevision &+= 1
            storage[keyID] = StoredValue(object: storedValue, revision: nextRevision)

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
    ) where Key: PersistentKeyProtocol {
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
            observations.removeAll {
                $0.observer == nil
            }

            observations.append(
                Observation(
                    observer: target,
                    keyID: keyID,
                    context: context
                )
            )
        }
    }

}

// MARK: - MigrationSnapshot Extension

extension InMemoryPersistentKeyValueStore {
    struct MigrationSnapshot {
        /// The store and key this snapshot belongs to.
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        /// Monotonically increasing revision used for conditional writes and removals.
        let revision: UInt64
        /// The captured value. Reference values are retained, not deep-copied; callers must keep them stable.
        let object: Any
    }
}

// MARK: - MigrationWrite Extension

extension InMemoryPersistentKeyValueStore {
    struct MigrationWrite {
        /// The store and key this prepared write belongs to.
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        /// The normalized value that will be committed.
        let object: Any
    }
}

// MARK: - Observation Extension

private extension InMemoryPersistentKeyValueStore {
    struct Observation {
        weak var observer: NSObject?
        let keyID: String
        let context: UnsafeMutableRawPointer?
    }
}

// MARK: - StoredValue Extension

private extension InMemoryPersistentKeyValueStore {
    struct StoredValue {
        let object: Any
        let revision: UInt64
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
