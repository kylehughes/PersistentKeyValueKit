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
/// A migration captures an exact copy of a Foundation property-list object stored as a key's value, such as an
/// `NSMutableArray` (including nested `NSDecimalNumber` values), and compares its contents so in-place edits fail the
/// migration instead of removing or overwriting the value. It detects other references only when they are replaced, so
/// do not mutate them while a migration runs. Same-type in-place rewrites compare the prepared result with `Equatable`
/// and fail at ``PersistentKeyMigrationReport/FailureStage/prepare`` with
/// ``PersistentKeyMigrationError/nonIdempotentRewrite`` when the value type does not conform to `Equatable`.
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
    /// Use this method to implement a custom key's in-memory `get(from:)` requirement of ``PersistentKeyProtocol``,
    /// passing the key's ``PersistentKeyProtocol/id``, because observation and migration find the key's entry by its
    /// identifier. Typed call sites should use ``get(_:)`` instead.
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
    /// ``PersistentKeyProtocol``, passing the key's ``PersistentKeyProtocol/id``, because observation and migration
    /// find the key's entry by its identifier. Typed call sites should use ``remove(_:)`` instead.
    ///
    /// - Parameter key: The identifier of the entry.
    public func removeObject(forKey key: String) {
        let (removedValue, observations) = withLock {
            (storage.removeValue(forKey: key), registeredObservations(for: key))
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
    /// Use this method to implement a custom key's in-memory `set(to:in:)` requirement of ``PersistentKeyProtocol``,
    /// passing the key's ``PersistentKeyProtocol/id``, because observation and migration find the key's entry by its
    /// identifier. Typed call sites should use ``set(_:to:)`` instead.
    ///
    /// - Parameter value: The value to store.
    /// - Parameter key: The identifier of the entry.
    public func set<Value>(_ value: Value, forKey key: String) {
        let storedValue = Self.normalizedValue(value)

        let (replacedValue, observations) = withLock {
            nextRevision &+= 1

            return (
                storage.updateValue(StoredValue(object: storedValue, revision: nextRevision), forKey: key),
                registeredObservations(for: key)
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

    /// Returns the registrations for `keyID`. Must be called with the lock held.
    ///
    /// Registrations whose observer has been deallocated are skipped by notification and released on the next
    /// registration or deregistration, so this does not read the weak observers.
    private func registeredObservations(for keyID: String) -> [Observation] {
        observations.filter {
            $0.keyID == keyID
        }
    }

    /// Removes the registrations whose observer has been deallocated or that `isRemoved` selects for their live
    /// observer, returning every live observer read. Must be called with the lock held.
    ///
    /// Reading a weak observer retains it, and that reference becomes the last one if the observer is released on
    /// another thread. An observer's `deinit` can deregister, so the caller releases the returned observers only after
    /// the lock is unlocked.
    private func removeObservations(where isRemoved: (NSObject, Observation) -> Bool) -> [NSObject] {
        var liveObservers: [NSObject] = []

        observations.removeAll { observation in
            guard let observer = observation.observer else {
                return true
            }

            liveObservers.append(observer)

            return isRemoved(observer, observation)
        }

        return liveObservers
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

    var migrationHandle: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// Commits a prepared write only when the replacement snapshot is still current.
    ///
    /// Contents are compared before taking the lock, because comparing a Foundation collection can run code outside
    /// this store.
    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        guard write.identity == migrationIdentity else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        if let snapshot, snapshot.identity != migrationIdentity || snapshot.keyID != write.keyID {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        if let snapshot, !snapshot.hasContents(of: object(forKey: write.keyID)) {
            throw PersistentKeyMigrationError.destinationChanged
        }

        let result: (UInt64, [Observation], StoredValue?) = try withLock {
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
            return (nextRevision, registeredObservations(for: write.keyID), replacedValue)
        }

        let committed = MigrationSnapshot(
            identity: migrationIdentity,
            keyID: write.keyID,
            revision: result.0,
            object: write.object
        )
        notify(result.1, keyPath: write.keyID)
        guard try migrationSnapshotIsCurrent(committed, for: write.keyID) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return committed
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        false
    }

    /// Storage is keyed by Swift `String`, so canonically equivalent identifiers name one entry.
    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        .canonical(keyID)
    }

    /// Captures the persisted value and revision for a key, or `nil` when the key is absent.
    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        let storedValue = withLock {
            storage[keyID]
        }

        return storedValue.map {
            MigrationSnapshot(identity: migrationIdentity, keyID: keyID, revision: $0.revision, object: $0.object)
        }
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        let storedValue = withLock {
            storage[keyID]
        }

        return storedValue?.revision == snapshot.revision && snapshot.hasContents(of: storedValue?.object)
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

    /// Returns the value a prepared write would store, cast to the requested key's value type.
    func migrationValue<Key>(
        for key: Key,
        writtenBy write: MigrationWrite
    ) throws -> Key.Value? where Key: PersistentKeyProtocol {
        guard write.identity == migrationIdentity, write.keyID == key.id else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        guard let value = write.object as? Key.Value else {
            throw PersistentKeyValueConversionError.invalidValue
        }

        return value
    }

    /// Compares prepared values with `==`. Values that are not `Equatable` never match, because the store cannot tell
    /// whether they are the same.
    func migrationWrite(_ write: MigrationWrite, matches other: MigrationWrite) -> Bool {
        guard let value = write.object as? any Equatable else {
            return false
        }

        return value.isEqual(toMigrationObject: other.object)
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

        guard snapshot.hasContents(of: object(forKey: keyID)) else {
            throw PersistentKeyMigrationError.sourceChanged
        }

        let (removedValue, observations) = try withLock {
            () -> (StoredValue?, [Observation]) in
            guard storage[keyID]?.revision == snapshot.revision else {
                throw PersistentKeyMigrationError.sourceChanged
            }

            return (storage.removeValue(forKey: keyID), registeredObservations(for: keyID))
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

        let liveObservers = withLock {
            removeObservations { registeredObserver, observation in
                registeredObserver === observer && observation.keyID == keyID && observation.context == context
            }
        }

        // Release the observers after the lock is unlocked.
        withExtendedLifetime(liveObservers) {}
    }

    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let keyID = key.id

        let liveObservers = withLock {
            let liveObservers = removeObservations { _, _ in
                false
            }

            observations.append(
                Observation(
                    observer: target,
                    keyID: keyID,
                    context: context
                )
            )

            return liveObservers
        }

        // Release the observers after the lock is unlocked.
        withExtendedLifetime(liveObservers) {}
    }

}

// MARK: - MigrationSnapshot Extension

extension InMemoryPersistentKeyValueStore {
    /// A captured entry, which is current while the store holds the same revision with the same contents.
    ///
    /// Mutating a stored reference changes the entry without a new revision. A Foundation property-list object, such
    /// as an `NSMutableArray`, is therefore also captured as an exact immutable copy whose contents must still match.
    /// Other references, including ones inside Swift values, are retained but not copied, so they verify by revision
    /// only.
    struct MigrationSnapshot {
        /// The store and key this snapshot belongs to.
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        /// Monotonically increasing revision used for conditional writes and removals.
        let revision: UInt64
        /// The captured value.
        let object: Any
        /// An exact immutable copy of `object` when it is a Foundation property-list object, or `nil` otherwise.
        let contents: Any?

        // MARK: Internal Initialization

        init(identity: PersistentKeyValueMigrationStoreIdentity, keyID: String, revision: UInt64, object: Any) {
            self.identity = identity
            self.keyID = keyID
            self.revision = revision
            self.object = object
            contents = Self.frozenContents(of: object)
        }

        // MARK: Internal Instance Interface

        /// Whether `object`, the entry's current value, still has the captured contents.
        func hasContents(of object: Any?) -> Bool {
            guard let contents else {
                return true
            }

            return PropertyListMigrationStorage.equal(contents, object)
        }

        // MARK: Private Static Interface

        /// Returns an exact immutable copy of `object` when it, or the value an optional wraps, is a Foundation
        /// property-list object, whose contents can change without a store write.
        ///
        /// The copy keeps values that a serialized property list cannot, such as an `NSDecimalNumber`, so an edit to
        /// one is still detected.
        private static func frozenContents(of object: Any) -> Any? {
            var value = object
            while let optional = value as? any OptionalElement {
                guard let wrapped = optional.wrappedObject else {
                    return nil
                }

                value = wrapped
            }

            guard type(of: value) is AnyClass else {
                return nil
            }

            return try? PropertyListMigrationStorage.exactCopy(value)
        }
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

// MARK: - Equatable Extension

extension Equatable {
    /// Whether `object`, a stored value, is this value.
    fileprivate func isEqual(toMigrationObject object: Any) -> Bool {
        (object as? Self) == self
    }
}

// MARK: - Observation Extension

private extension InMemoryPersistentKeyValueStore {
    /// A registration for one observer, key, and context.
    ///
    /// This is a class because copying a weak reference to an Objective-C object briefly retains the object, and that
    /// reference can be the last one. Copying a registration copies only a reference to it, so the store can copy its
    /// registrations with the lock held.
    final class Observation {
        weak var observer: NSObject?
        let keyID: String
        let context: UnsafeMutableRawPointer?

        init(observer: NSObject, keyID: String, context: UnsafeMutableRawPointer?) {
            self.observer = observer
            self.keyID = keyID
            self.context = context
        }
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

extension OptionalElement {
    /// The wrapped value, if any, as `Any`.
    fileprivate var wrappedObject: Any? {
        optionalValue.map {
            $0 as Any
        }
    }
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
