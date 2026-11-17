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
/// elements out of Swift arrays and dictionaries of optionals) and records an explicit entry when an optional key is
/// set to `nil`. Calling ``remove(_:)`` deletes the entry. Migrations read and write the stored Swift value directly
/// without calling the key's representation `decode` or `encode`. When migrating a stored `nil` from an in-memory store
/// to `UserDefaults` or `NSUbiquitousKeyValueStore` with
/// ``PersistentKeyCopyConflictPolicy/overwriteDestination`` or
/// ``PersistentKeyMoveConflictPolicy/overwriteDestination``, the destination key is removed.
///
/// Because the store keeps the Swift value itself rather than an encoded copy, a class-typed value is shared, not
/// copied: every read returns the same instance that was written, and mutating it changes the stored value. Use
/// immutable or `Sendable` reference types for values that are read or written from more than one concurrency domain.
///
/// - Important: Storage access is protected by a lock so this type satisfies ``PersistentKeyValueStore``'s
///   thread-safety requirement. The lock is not held while key identifiers are evaluated, observers are notified, or
///   replaced values are released, so that code can access the store again.
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

    // MARK: Public Instance Interface

    /// Returns the stored value for the given key, or `nil` if the store has no entry for the key.
    ///
    /// An entry recorded by setting an optional value to `nil` is returned as a non-`nil` `Any` that wraps `nil`;
    /// cast the result to the optional type to read it. Swift arrays and dictionaries of optionals are returned without
    /// their `nil` elements.
    ///
    /// Use this method to implement a custom key's in-memory `get(from:)` requirement of ``PersistentKeyProtocol``.
    /// Typed call sites should use ``get(_:)`` instead.
    ///
    /// - Parameter key: The identifier of the entry.
    /// - Returns: The stored value, or `nil` if the store has no entry for the key.
    public func object(forKey key: String) -> Any? {
        withLock {
            storage[key]?.object
        }
    }

    /// Removes the entry for the given key and notifies observers of the key.
    ///
    /// Use this method to implement a custom key's in-memory `remove(from:)` requirement of
    /// ``PersistentKeyProtocol``. Typed call sites should use ``remove(_:)`` instead.
    ///
    /// - Parameter key: The identifier of the entry.
    public func removeObject(forKey key: String) {
        let (removedValue, observations) = withLock {
            (storage.removeValue(forKey: key), liveObservations(for: key))
        }

        notify(observations, keyPath: key)

        // Releasing the last reference can run a `deinit` that reads this store, so release it after unlocking.
        withExtendedLifetime(removedValue) {}
    }

    /// Stores the given value for the given key and notifies observers of the key.
    ///
    /// The store keeps the Swift value itself, without converting it to a property-list type. It removes `nil`
    /// elements from a Swift array or `String`-keyed dictionary of optionals when the result is still a `Value`, so a
    /// read of the same type returns the stored value; other values, including Foundation collections such as
    /// `NSMutableArray`, are stored unchanged. Passing an optional that is `nil` records an explicit entry that
    /// ``object(forKey:)`` returns; call ``removeObject(forKey:)`` to delete the entry.
    ///
    /// Use this method to implement a custom key's in-memory `set(to:in:)` requirement of ``PersistentKeyProtocol``.
    /// Typed call sites should use ``set(_:to:)`` instead.
    ///
    /// - Parameter value: The value to store.
    /// - Parameter key: The identifier of the entry.
    public func set<Value>(_ value: Value, forKey key: String) {
        let storedValue = Self.normalizedValue(value)

        let (replacedValue, observations) = withLock {
            nextRevision &+= 1

            return (
                storage.updateValue(StoredValue(object: storedValue, revision: nextRevision), forKey: key),
                liveObservations(for: key)
            )
        }

        notify(observations, keyPath: key)

        // Releasing the last reference can run a `deinit` that reads this store, so release it after unlocking.
        withExtendedLifetime(replacedValue) {}
    }

    // MARK: Private Static Interface

    /// Returns `value` without the `nil` elements of a Swift array or dictionary of optionals, or `value` itself when
    /// it is not such a collection or the compacted collection is not a `Value`.
    private static func normalizedValue<Value>(_ value: Value) -> Any {
        guard let collection = value as? any OptionalElementCollection else {
            return value
        }

        let compactedValue = collection.compactedValue()

        guard compactedValue is Value else {
            return value
        }

        return compactedValue
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
        let result: (MigrationSnapshot, [Observation], StoredValue?) = try withLock {
            guard write.identity == migrationIdentity else {
                throw PersistentKeyMigrationError.internalInconsistency
            }

            if let snapshot, snapshot.identity != migrationIdentity || snapshot.keyID != write.keyID {
                throw PersistentKeyMigrationError.internalInconsistency
            }

            if let snapshot, storage[write.keyID]?.revision != snapshot.revision {
                throw PersistentKeyMigrationError.destinationChanged
            }

            if snapshot == nil, storage[write.keyID] != nil {
                throw PersistentKeyMigrationError.destinationChanged
            }

            nextRevision &+= 1
            let replacedValue = storage.updateValue(
                StoredValue(object: write.object, revision: nextRevision),
                forKey: write.keyID
            )
            let committed = MigrationSnapshot(
                identity: migrationIdentity,
                keyID: write.keyID,
                revision: nextRevision,
                object: write.object
            )
            return (committed, liveObservations(for: write.keyID), replacedValue)
        }

        notify(result.1, keyPath: write.keyID)
        guard try migrationSnapshotIsCurrent(result.0, for: write.keyID) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return result.0
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        false
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
            throw PersistentKeyMigrationError.internalInconsistency
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
            throw PersistentKeyMigrationError.internalInconsistency
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
        MigrationWrite(identity: migrationIdentity, keyID: key.id, object: Self.normalizedValue(value))
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        let (removedValue, observations) = try withLock {
            () -> (StoredValue?, [Observation]) in
            guard storage[keyID]?.revision == snapshot.revision else {
                throw PersistentKeyMigrationError.sourceChanged
            }

            return (storage.removeValue(forKey: keyID), liveObservations(for: keyID))
        }

        notify(observations, keyPath: keyID)
        withExtendedLifetime(removedValue) {}
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
        key.get(from: self)
    }

    // MARK: Setting Values

    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        key.set(to: value, in: self)
    }

    // MARK: Removing Values

    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        key.remove(from: self)
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

// MARK: - Optional Element Collections

/// A Swift collection whose `nil` elements the in-memory store removes, matching the property-list stores.
private protocol OptionalElementCollection {
    func compactedValue() -> Any
}

/// An `Optional`, used to constrain ``OptionalElementCollection`` conformances to collections of optionals.
private protocol OptionalElement {
    associatedtype Wrapped

    var optionalValue: Wrapped? { get }
}

extension Optional: OptionalElement {
    fileprivate var optionalValue: Wrapped? {
        self
    }
}

extension Array: OptionalElementCollection where Element: OptionalElement {
    fileprivate func compactedValue() -> Any {
        compactMap(\.optionalValue)
    }
}

extension Dictionary: OptionalElementCollection where Key == String, Value: OptionalElement {
    fileprivate func compactedValue() -> Any {
        compactMapValues(\.optionalValue)
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
