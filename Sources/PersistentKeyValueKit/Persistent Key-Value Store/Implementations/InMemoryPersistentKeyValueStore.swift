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
/// elements out of a top-level Swift array or dictionary of optionals) and records an explicit entry when an optional
/// key is set to `nil` through the default in-memory setter. Calling ``remove(_:)`` deletes the entry. Migrations read
/// and write the stored Swift value directly without calling the key's representation `decode` or `encode` for an
/// in-memory source or destination. When migrating a stored `nil` from an in-memory store to `UserDefaults` or
/// `NSUbiquitousKeyValueStore` with ``PersistentKeyCopyConflictPolicy/overwriteDestination`` or
/// ``PersistentKeyMoveConflictPolicy/overwriteDestination``, the destination key is removed if its representation
/// encodes that `nil` as `nil`, as the built-in optional representation does; a custom optional representation that
/// encodes `nil` as an object writes that object. A migration into the store applies the
/// ordinary setter's shallow compaction to a qualifying array or dictionary of optionals, including one wrapped in an
/// `Optional`. An explicit `nil` entry counts as an existing destination value.
///
/// The store treats identifiers as Swift strings, so canonically equivalent spellings, and identifiers that differ only
/// in unpaired UTF-16 surrogates, which Swift repairs, name one entry. Foundation stores keep them distinct. Migration
/// duplicate, overlap, and same-store checks use the same rule.
///
/// A manual observer registered with ``register(observer:for:with:and:)`` is called synchronously on the writing thread
/// through `observeValue(forKeyPath:of:change:context:)` by every write or removal, with the identifier that the
/// operation received as the key path, `nil` for `change`, and the registered context. One call to
/// ``deregister(_:for:context:)`` removes every matching registration.
///
/// Because the store keeps the Swift value itself rather than an encoded copy, a class-typed value is shared, not
/// copied: every read returns the same instance that was written, and mutating it changes the stored value without
/// notifying key observers, which only a write or removal through the store notifies. Use
/// immutable or `Sendable` reference types for values that are read or written from more than one concurrency domain.
/// A migration captures an exact copy of a Foundation property-list object that it reads or prepares as a key's value,
/// such as an `NSMutableArray` (including nested `NSDecimalNumber` values), and compares its contents, including each
/// integer's width, before it overwrites a destination value, removes a move's source, or verifies a write, so an
/// in-place edit fails the migration at that step instead of the value being replaced or removed. A `copy` does not
/// recheck its source after reading it. The migration detects other references only when they are replaced, so do not
/// mutate them while a migration runs.
///
/// - Important: Storage access is protected by a lock so this type satisfies ``PersistentKeyValueStore``'s
///   thread-safety requirement. The lock is not held while key identifiers are evaluated, an identifier bridged from an
///   `NSString` is copied, observers are notified, or replaced or removed values and identifiers are released, so that
///   code can access the store again.
public final class InMemoryPersistentKeyValueStore: @unchecked Sendable {
    /// The stable identity of this in-memory store for migration operations.
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity

    private let lock: NSLock
    /// The revision of the most recently stored entry. Every stored entry takes a new revision, so migration
    /// verification can rely on a revision never being reused for a replaced or removed entry.
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
        Self.withStorageKey(for: key) { storageKey in
            withLock {
                storage[storageKey]?.object
            }
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
        let (removedEntry, observations) = Self.withStorageKey(for: key) { storageKey in
            withLock {
                (removeEntry(forKey: storageKey), registeredObservations(for: storageKey))
            }
        }

        notify(observations, keyPath: key)

        // Releasing the last reference to the value or its identifier can run a `deinit` that reads this store, so
        // release them after unlocking.
        withExtendedLifetime(removedEntry) {}
    }

    /// Stores the given value for the given key and notifies observers of the key.
    ///
    /// The store keeps the Swift value itself, without converting it to a property-list type. It removes `nil`
    /// elements from a top-level Swift array or `String`-keyed dictionary of optionals when the result is still a
    /// `Value`, so a read of the same type returns the stored value; other values, including Foundation collections
    /// such as `NSMutableArray`, are stored unchanged. Passing an optional that is `nil` records an explicit entry that
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

        let (replacedValue, observations) = Self.withStorageKey(for: key) { storageKey in
            withLock {
                nextRevision &+= 1

                return (
                    storage.updateValue(StoredValue(object: storedValue, revision: nextRevision), forKey: storageKey),
                    registeredObservations(for: storageKey)
                )
            }
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

    /// Returns `keyID` with contiguous UTF-8 storage, copying it only when it has none. The result equals `keyID`, so
    /// it names the same entry.
    ///
    /// The lock is held while identifiers are hashed and compared. Swift reads contiguous UTF-8 directly, but reads an
    /// identifier bridged lazily from an `NSString` through the object's methods, which can run arbitrary code, such as
    /// a subclass's character accessor that reads this store. A native Swift string is returned without copying. So is
    /// a bridged string whose contents Foundation already stores as contiguous UTF-8, which keeps its object, so the
    /// store releases identifiers only after unlocking.
    private static func storageKey(for keyID: String) -> String {
        var storageKey = keyID
        storageKey.makeContiguousUTF8()

        return storageKey
    }

    /// Calls `body` with the ``storageKey(for:)`` of `keyID`, passing `keyID` itself when it already has contiguous
    /// UTF-8 storage.
    ///
    /// Ordinary reads and writes use this, because returning even an uncopied identifier from ``storageKey(for:)``
    /// retains it, which measurably slows the fastest store operations.
    @inline(__always)
    private static func withStorageKey<Result>(for keyID: String, _ body: (String) -> Result) -> Result {
        guard !keyID.isContiguousUTF8 else {
            return body(keyID)
        }

        return body(storageKey(for: keyID))
    }

    // MARK: Private Instance Interface

    /// Removes and returns the entry for `storageKey`, or returns `nil` if the store has no entry for it. Must be
    /// called with the lock held.
    ///
    /// The entry's stored identifier can hold the last reference to a bridged `NSString`, so the caller releases the
    /// entry after unlocking.
    private func removeEntry(forKey storageKey: String) -> (key: String, value: StoredValue)? {
        storage.index(forKey: storageKey).map {
            storage.remove(at: $0)
        }
    }

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
    /// observer, marking the selected registrations inactive, and returns every live observer read and every removed
    /// registration. Must be called with the lock held.
    ///
    /// Reading a weak observer retains it, and that reference becomes the last one if the observer is released on
    /// another thread. A removed registration can hold the last reference to a bridged `NSString` identifier. Releasing
    /// either can run a `deinit` that accesses this store, so the caller releases the returned references only after
    /// the lock is unlocked.
    private func removeObservations(where isRemoved: (NSObject, Observation) -> Bool) -> [AnyObject] {
        var references: [AnyObject] = []

        observations.removeAll { observation in
            guard let observer = observation.observer else {
                references.append(observation)

                return true
            }

            references.append(observer)
            observation.isActive = !isRemoved(observer, observation)

            guard !observation.isActive else {
                return false
            }

            references.append(observation)

            return true
        }

        return references
    }

    /// Notifies each registration in `observations` that is still active when its turn comes.
    ///
    /// An observer's callback can deregister a later registration in `observations`, and that registration must not be
    /// called after ``deregister(_:for:context:)`` returns, so each registration is checked with the lock held just
    /// before it is called. The observer is retained by that read and released after the lock is unlocked.
    private func notify(_ observations: [Observation], keyPath: String?) {
        for observation in observations {
            let observer = withLock {
                observation.isActive ? observation.observer : nil
            }

            observer?.observeValue(
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
    ///
    /// Contents are compared before taking the lock, because comparing a Foundation collection can run code outside
    /// this store. The committed snapshot carries the contents captured when the write was prepared, because once the
    /// value is stored, another thread can read and change it before a copy taken now.
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

        let storageKey = Self.storageKey(for: write.keyID)

        let result: (UInt64, [Observation], StoredValue?) = try withLock {
            if let snapshot, storage[storageKey]?.revision != snapshot.revision {
                throw PersistentKeyMigrationError.destinationChanged
            }

            if snapshot == nil, storage[storageKey] != nil {
                throw PersistentKeyMigrationError.destinationChanged
            }

            nextRevision &+= 1
            let replacedValue = storage.updateValue(
                StoredValue(object: write.object, revision: nextRevision),
                forKey: storageKey
            )
            return (nextRevision, registeredObservations(for: storageKey), replacedValue)
        }

        let committed = MigrationSnapshot(committing: write, revision: result.0)
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
    ///
    /// The migration registry hashes and compares identities with its lock held, so an identity holds its identifier
    /// as storage does.
    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        .canonical(Self.storageKey(for: keyID))
    }

    /// Captures the persisted value and revision for a key, or `nil` when the key is absent.
    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        let storageKey = Self.storageKey(for: keyID)

        let storedValue = withLock {
            storage[storageKey]
        }

        return storedValue.map {
            MigrationSnapshot(identity: migrationIdentity, keyID: keyID, revision: $0.revision, object: $0.object)
        }
    }

    /// Whether the store still holds the snapshot's revision with the captured contents.
    ///
    /// Contents are compared before the revision is checked, because comparing a Foundation collection can run code
    /// that writes or removes the entry. A store never reuses a revision, so a matching revision afterwards means the
    /// compared value was the snapshot's entry and the entry was not replaced or removed during the comparison.
    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        guard snapshot.hasContents(of: object(forKey: keyID)) else {
            return false
        }

        let storageKey = Self.storageKey(for: keyID)

        return withLock {
            storage[storageKey]?.revision == snapshot.revision
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

        guard snapshot.hasContents(of: object(forKey: keyID)) else {
            throw PersistentKeyMigrationError.sourceChanged
        }

        let storageKey = Self.storageKey(for: keyID)

        let (removedEntry, observations) = try withLock {
            () -> ((key: String, value: StoredValue)?, [Observation]) in
            guard storage[storageKey]?.revision == snapshot.revision else {
                throw PersistentKeyMigrationError.sourceChanged
            }

            return (removeEntry(forKey: storageKey), registeredObservations(for: storageKey))
        }

        notify(observations, keyPath: keyID)
        withExtendedLifetime(removedEntry) {}
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
        let keyID = Self.storageKey(for: key.id)

        let references = withLock {
            removeObservations { registeredObserver, observation in
                registeredObserver === observer && observation.keyID == keyID && observation.context == context
            }
        }

        // Release the observers and registrations after the lock is unlocked.
        withExtendedLifetime(references) {}
    }

    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let keyID = Self.storageKey(for: key.id)

        let references = withLock {
            let references = removeObservations { _, _ in
                false
            }

            observations.append(
                Observation(
                    observer: target,
                    keyID: keyID,
                    context: context
                )
            )

            return references
        }

        // Release the observers and registrations after the lock is unlocked.
        withExtendedLifetime(references) {}
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

        /// Creates the snapshot of `write` committed at `revision`, with the contents captured when it was prepared.
        init(committing write: MigrationWrite, revision: UInt64) {
            identity = write.identity
            keyID = write.keyID
            self.revision = revision
            object = write.object
            contents = write.contents
        }

        // MARK: Internal Instance Interface

        /// Whether `object`, the entry's current value, still has the captured contents.
        func hasContents(of object: Any?) -> Bool {
            guard let contents else {
                return true
            }

            // The store keeps objects unserialized, so an edit that changes only an integer's width is a change.
            return PropertyListMigrationStorage.equal(contents, object, distinguishingIntegerWidths: true)
        }

        // MARK: Internal Static Interface

        /// Returns an exact immutable copy of `object` when it, or the value an optional wraps, is a Foundation
        /// property-list object, whose contents can change without a store write.
        ///
        /// The copy keeps values that a serialized property list cannot, such as an `NSDecimalNumber`, so an edit to
        /// one is still detected.
        static func frozenContents(of object: Any) -> Any? {
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
        /// An exact immutable copy of `object` when it is a Foundation property-list object, or `nil` otherwise,
        /// captured before `object` is stored so that verification compares against the prepared contents.
        let contents: Any?

        // MARK: Internal Initialization

        init(identity: PersistentKeyValueMigrationStoreIdentity, keyID: String, object: Any) {
            self.identity = identity
            self.keyID = keyID
            self.object = object
            contents = MigrationSnapshot.frozenContents(of: object)
        }
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
        /// Whether the registration is still registered. Removing a registration with a live observer clears this, so
        /// a notification that copied the registration earlier skips it. Read and written only with the store's lock
        /// held.
        var isActive = true

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

/// An `Optional`, used to constrain ``OptionalElementCollection`` conformances to collections of optionals and to
/// find a `nil` value during migration.
protocol OptionalElement {
    associatedtype Wrapped

    var optionalValue: Wrapped? { get }
}

extension OptionalElement {
    /// The wrapped value, if any, as `Any`.
    var wrappedObject: Any? {
        optionalValue.map {
            $0 as Any
        }
    }
}

extension Optional: OptionalElement {
    var optionalValue: Wrapped? {
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
