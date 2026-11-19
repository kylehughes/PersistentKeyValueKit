import Foundation

/// Synchronizes in-process migration ownership; store operations never run under this lock.
private final class PersistentKeyMigrationRegistry: @unchecked Sendable {
    static let shared = PersistentKeyMigrationRegistry()

    private let lock = NSLock()
    private var resources = Set<Resource>()

    // MARK: Private Initialization

    private init() {
    }

    // MARK: Internal Instance Interface

    func claim(_ values: Set<Resource>) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard values.isDisjoint(with: resources) else {
            return false
        }

        resources.formUnion(values)
        return true
    }

    func release(_ values: Set<Resource>) {
        lock.lock()
        resources.subtract(values)
        lock.unlock()
    }
}

// MARK: - Resource Extension

private extension PersistentKeyMigrationRegistry {
    struct Resource: Hashable {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let key: PersistentKeyMigrationKeyIdentity
    }
}

// MARK: - Migration Operation

enum PersistentKeyMigrationOperation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)

    // MARK: Internal Instance Interface

    /// Whether the operation leaves both values in place when the destination already holds one.
    var keepsSourceAndDestination: Bool {
        switch self {
        case .copy(let policy):
            policy == .keepDestination
        case .move(let policy):
            policy == .keepBoth
        }
    }
}

// MARK: - Migration Mapping

/// The type-erased contents of a ``PersistentKeyMigrationItem``.
///
/// Erasure lets a batch mix value types while each item still decodes with its source key and encodes with its
/// destination key.
protocol PersistentKeyMigrationMappingProtocol: Sendable {
    var destinationKeyID: String { get }

    var sourceKeyID: String { get }

    func migrate<SourceStore, DestinationStore>(
        from sourceStore: SourceStore,
        to destinationStore: DestinationStore,
        operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport.Outcome
    where
        SourceStore: PersistentKeyValueMigrationBackend,
        DestinationStore: PersistentKeyValueMigrationBackend
}

struct PersistentKeyMigrationMapping<SourceKey, DestinationKey>: PersistentKeyMigrationMappingProtocol
where SourceKey: PersistentKeyProtocol, DestinationKey: PersistentKeyProtocol {
    let destination: DestinationKey
    let source: SourceKey
    let transform: @Sendable (SourceKey.Value) throws -> DestinationKey.Value

    // MARK: Internal Initialization

    init(
        source: SourceKey,
        destination: DestinationKey,
        transform: @escaping @Sendable (SourceKey.Value) throws -> DestinationKey.Value
    ) {
        self.source = source
        self.destination = destination
        self.transform = transform
    }

    // MARK: Internal Instance Interface

    var destinationKeyID: String {
        destination.id
    }

    var sourceKeyID: String {
        source.id
    }

    func migrate<SourceStore, DestinationStore>(
        from sourceStore: SourceStore,
        to destinationStore: DestinationStore,
        operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport.Outcome
    where
        SourceStore: PersistentKeyValueMigrationBackend,
        DestinationStore: PersistentKeyValueMigrationBackend
    {
        let sourceID = source.id
        let destinationID = destination.id
        guard source.isMigrationEnabled, destination.isMigrationEnabled else {
            return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .keyDisabled)
        }

        var stage: PersistentKeyMigrationReport.FailureStage = .snapshot
        do {
            guard let sourceSnapshot = try sourceStore.migrationSnapshot(for: sourceID) else {
                return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .sourceAbsent)
            }

            let destinationSnapshot = try destinationStore.migrationSnapshot(for: destinationID)
            if let destinationSnapshot, operation.keepsSourceAndDestination {
                // Reading the destination to capture its snapshot runs its value's code, and the source snapshot can
                // hold the last reference to the source value, whose `deinit` can change the destination. Either can
                // remove the kept value, so the source snapshot is released and keeping the destination is verified
                // like a write.
                _ = consume sourceSnapshot
                stage = .write
                guard try destinationStore.migrationSnapshotIsCurrent(destinationSnapshot, for: destinationID) else {
                    throw PersistentKeyMigrationError.destinationChanged
                }

                return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .keptDestination)
            }

            if case .move(.keepDestinationAndRemoveSource) = operation, let destinationSnapshot {
                // Keeping the destination is verified like a write, so a change found here, before the source is
                // removed, fails at the same stage as a change found while writing.
                stage = .write
                guard try destinationStore.migrationSnapshotIsCurrent(destinationSnapshot, for: destinationID) else {
                    throw PersistentKeyMigrationError.destinationChanged
                }

                stage = .cleanup
                try Self.remove(consume sourceSnapshot, from: sourceStore, for: sourceID)
                // Removal can notify observers synchronously, and they can change the destination. Comparing the
                // destination runs its value's code, which can restore the source, so the source is checked last.
                guard try destinationStore.migrationSnapshotIsCurrent(destinationSnapshot, for: destinationID) else {
                    throw PersistentKeyMigrationError.destinationChanged
                }

                try Self.verifyRemoval(from: sourceStore, for: sourceID)

                return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .discardedSource)
            }

            stage = .decode
            let value = try sourceStore.migrationValue(for: source, in: sourceSnapshot)
            // The decoded value can be the instance stored in the source, the destination snapshot can hold the
            // instance being replaced, and the prepared write can hold the last reference to the encoded object. A
            // `deinit` of any of them can change a key, so each is released at its last use, before the write and
            // removal are verified.
            stage = .transform
            let destinationValue = try transform(consume value)
            stage = .prepare
            let write = try destinationStore.prepareMigrationWrite(consume destinationValue, for: destination)
            stage = .write
            let committedSnapshot = try Self.commit(
                consume write,
                replacing: consume destinationSnapshot,
                in: destinationStore,
                for: destinationID
            )

            if case .move = operation {
                stage = .cleanup
                try Self.remove(consume sourceSnapshot, from: sourceStore, for: sourceID)
                // Removal can notify observers synchronously, and they can change the destination. Comparing the
                // destination runs its value's code, which can restore the source, so the source is checked last.
                guard try Self.isCommitted(committedSnapshot, in: destinationStore, for: destinationID) else {
                    throw PersistentKeyMigrationError.destinationChanged
                }

                try Self.verifyRemoval(from: sourceStore, for: sourceID)

                return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .moved)
            }

            // The source snapshot can hold the last reference to the copied value, whose `deinit` can change the
            // destination, so it is released and the destination is verified again.
            _ = consume sourceSnapshot
            guard try Self.isCommitted(committedSnapshot, in: destinationStore, for: destinationID) else {
                throw PersistentKeyMigrationError.writeVerificationFailed
            }

            return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .copied)
        } catch {
            return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, failedAt: stage, error: error)
        }
    }

    // MARK: Private Static Interface

    /// Commits `write` in place of `snapshot`, throwing ``PersistentKeyMigrationError/writeVerificationFailed`` unless
    /// `store` then holds the committed value.
    ///
    /// The write can hold the last reference to the encoded object, and the snapshot to the replaced value. A
    /// `deinit` of either, including a Core Foundation allocator's cleanup, can change the key, so both are released
    /// before the write is verified.
    private static func commit<Store>(
        _ write: consuming Store.MigrationWrite,
        replacing snapshot: consuming Store.MigrationSnapshot?,
        in store: Store,
        for keyID: String
    ) throws -> Store.MigrationSnapshot? where Store: PersistentKeyValueMigrationBackend {
        let committedSnapshot = try store.commitMigrationWrite(write, replacing: snapshot)
        _ = consume write
        _ = consume snapshot
        guard try isCommitted(committedSnapshot, in: store, for: keyID) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return committedSnapshot
    }

    /// Whether `store` still holds the value committed as `snapshot`, where `nil` means the write removed the key.
    private static func isCommitted<Store>(
        _ snapshot: Store.MigrationSnapshot?,
        in store: Store,
        for keyID: String
    ) throws -> Bool where Store: PersistentKeyValueMigrationBackend {
        guard let snapshot else {
            return try store.migrationSnapshot(for: keyID) == nil
        }

        return try store.migrationSnapshotIsCurrent(snapshot, for: keyID)
    }

    /// Removes the value captured as `snapshot`, throwing ``PersistentKeyMigrationError/sourceChanged`` if `store` no
    /// longer holds it and ``PersistentKeyMigrationError/removalVerificationFailed`` unless the key is then absent.
    ///
    /// The snapshot can hold the last reference to the removed value, whose `deinit` can write either key, so it is
    /// released before the removal is verified.
    private static func remove<Store>(
        _ snapshot: consuming Store.MigrationSnapshot,
        from store: Store,
        for keyID: String
    ) throws where Store: PersistentKeyValueMigrationBackend {
        guard try store.migrationSnapshotIsCurrent(snapshot, for: keyID) else {
            throw PersistentKeyMigrationError.sourceChanged
        }

        try store.removeMigrationValue(for: keyID, matching: snapshot)
        _ = consume snapshot
        try verifyRemoval(from: store, for: keyID)
    }

    /// Throws ``PersistentKeyMigrationError/removalVerificationFailed`` unless `store` holds no value for `keyID`.
    private static func verifyRemoval<Store>(
        from store: Store,
        for keyID: String
    ) throws where Store: PersistentKeyValueMigrationBackend {
        guard try store.migrationSnapshot(for: keyID) == nil else {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }
    }
}

// MARK: - PersistentKeyValueStore Extension

extension PersistentKeyValueStore {
    // MARK: Public Instance Interface

    /// Copies one item's persisted value from this store to another store.
    ///
    /// This is equivalent to calling ``copy(items:to:onConflict:tracking:)`` with `[item]`.
    ///
    /// - Parameter item: The item to copy.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value for the item's destination key in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report containing the item's outcome and the completion-tracking status.
    public func copy<Destination>(
        _ item: PersistentKeyMigrationItem,
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        try copy(items: [item], to: destination, onConflict: policy, tracking: tracking)
    }

    /// Copies a persisted value for one key from this store to the same key in another store.
    ///
    /// This is equivalent to calling ``copy(items:to:onConflict:tracking:)`` with `[.key(key)]`.
    ///
    /// - Parameter key: The key to copy.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report containing the key's outcome and the completion-tracking status.
    public func copy<Key, Destination>(
        _ key: Key,
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueStore {
        try copy(items: [.key(key)], to: destination, onConflict: policy, tracking: tracking)
    }

    /// Copies persisted values for the given keys from this store to the same keys in another store, in input order.
    ///
    /// A batch can contain keys with different value types. This is equivalent to calling
    /// ``copy(items:to:onConflict:tracking:)`` with each key wrapped in ``PersistentKeyMigrationItem/key(_:)``.
    ///
    /// - Parameter keys: The keys to copy, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report with one outcome per key in `keys`, or no outcomes if completion was already recorded.
    public func copy<Destination>(
        _ keys: [any PersistentKeyProtocol],
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        try copy(
            items: keys.map {
                .key($0)
            },
            to: destination,
            onConflict: policy,
            tracking: tracking
        )
    }

    /// Copies persisted values for the given items from this store to another store, in input order.
    ///
    /// Each item's value is read from its source key in this store, decoded with the source key's
    /// ``PersistentKeyProtocol/representation``, converted by the item's transform if it has one, encoded with the
    /// destination key's representation, and written to the destination key in `destination`. The source value is left
    /// in place. Only values persisted in each store's own domain participate; registered defaults, launch arguments,
    /// added suites, and key default values are neither copied nor treated as destination conflicts. When an existing
    /// destination value makes ``PersistentKeyCopyConflictPolicy/keepDestination`` keep it, neither value is decoded.
    ///
    /// When the conflict policy selects a write to a `UserDefaults` or `NSUbiquitousKeyValueStore` destination, the
    /// destination entry is removed only when the destination key's top-level encoding is `nil` and the value written
    /// is `nil` at an actual `Optional` layer, including `.some(nil)`. The built-in optional representation encodes its
    /// own `.none` as `nil` and delegates `.some` to its base representation. A value that is not `nil` at an
    /// `Optional` layer but whose top-level encoding is `nil` fails the item at
    /// ``PersistentKeyMigrationReport/FailureStage/prepare`` with ``PersistentKeyValueConversionError/encodingFailed``
    /// and writes neither entry, while the other items in the batch proceed independently. A custom optional
    /// representation that encodes `nil` as an object, such as a marker string, writes that object, so a `nil` value
    /// does not always remove the entry.
    ///
    /// `destination` can be this store when the items' source identifiers are unique, their destination identifiers are
    /// unique, and the two sets are disjoint.
    ///
    /// Setup failures are thrown before any item runs: missing domain metadata, an item that maps a key to itself
    /// within one store, duplicate source or destination key identifiers, a destination that is another item's source
    /// within one store, reserved completion-marker keys, key identifiers that exceed a store's limit, an empty
    /// migration identifier, or an overlapping in-process migration of the same keys or marker. Errors thrown by a
    /// store's ``PersistentKeyValueStore/migrationEndpoint`` or by reading the completion marker propagate unchanged.
    ///
    /// Per-item failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the remaining items continue,
    /// and the report is not discardable: inspect it or call ``PersistentKeyMigrationReport/throwIfIncomplete()``.
    /// Completed writes are not rolled back if a later item fails. An empty batch is valid; with completion tracking,
    /// it records the marker.
    ///
    /// The copy releases its references to the encoded value and to a replaced destination value before verifying the
    /// write, and to the source value before verifying the write again. Under
    /// ``PersistentKeyCopyConflictPolicy/keepDestination``, it releases the source value before verifying the kept
    /// destination value. Verification guards against the changes it can observe, including those these releases
    /// cause, but code that writes to a migrating store as a side effect of reading, encoding, or deallocating a value,
    /// such as a getter, `deinit`, allocator callback, or observer, is an uncoordinated writer. Coordinate such writers
    /// before migrating, as with other writers; otherwise, behavior is unspecified.
    ///
    /// Local completion does not guarantee disk durability or iCloud delivery. A copy into `NSUbiquitousKeyValueStore`
    /// posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` for each key it writes.
    ///
    /// - Parameter items: The items to copy, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values for destination keys in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report with one outcome per item in `items`, or no outcomes if completion was already recorded.
    public func copy<Destination>(
        items: [PersistentKeyMigrationItem],
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        let sourceEndpoint = try migrationEndpoint
        let destinationEndpoint = try destination.migrationEndpoint
        return try sourceEndpoint.backend.execute(
            items,
            destination: destinationEndpoint.backend,
            operation: .copy(policy),
            tracking: tracking
        )
    }

    /// Moves one item's persisted value from this store to another store.
    ///
    /// This is equivalent to calling ``move(items:to:onConflict:tracking:)`` with `[item]`.
    ///
    /// - Parameter item: The item to move.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value for the item's destination key in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report containing the item's outcome and the completion-tracking status.
    public func move<Destination>(
        _ item: PersistentKeyMigrationItem,
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        try move(items: [item], to: destination, onConflict: policy, tracking: tracking)
    }

    /// Moves a persisted value for one key from this store to the same key in another store.
    ///
    /// This is equivalent to calling ``move(items:to:onConflict:tracking:)`` with `[.key(key)]`.
    ///
    /// - Parameter key: The key to move.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report containing the key's outcome and the completion-tracking status.
    public func move<Key, Destination>(
        _ key: Key,
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueStore {
        try move(items: [.key(key)], to: destination, onConflict: policy, tracking: tracking)
    }

    /// Moves persisted values for the given keys from this store to the same keys in another store, in input order.
    ///
    /// A batch can contain keys with different value types. This is equivalent to calling
    /// ``move(items:to:onConflict:tracking:)`` with each key wrapped in ``PersistentKeyMigrationItem/key(_:)``.
    ///
    /// - Parameter keys: The keys to move, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report with one outcome per key in `keys`, or no outcomes if completion was already recorded.
    public func move<Destination>(
        _ keys: [any PersistentKeyProtocol],
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        try move(
            items: keys.map {
                .key($0)
            },
            to: destination,
            onConflict: policy,
            tracking: tracking
        )
    }

    /// Moves persisted values for the given items from this store to another store, in input order.
    ///
    /// Each item's value is read from its source key in this store, decoded with the source key's
    /// ``PersistentKeyProtocol/representation``, converted by the item's transform if it has one, encoded with the
    /// destination key's representation, and written to the destination key in `destination`. After the write is
    /// verified, or when ``PersistentKeyMoveConflictPolicy/keepDestinationAndRemoveSource`` resolves a conflict, the
    /// source value is removed. Under ``PersistentKeyMoveConflictPolicy/keepBoth``, a conflicting source value is left
    /// in place. When an existing destination value makes a keep policy resolve the conflict, neither value is decoded,
    /// so ``PersistentKeyMoveConflictPolicy/keepDestinationAndRemoveSource`` removes the source even if it cannot be
    /// decoded. Only values persisted in each store's own domain participate; registered defaults, launch arguments,
    /// added suites, and key default values are neither moved nor treated as destination conflicts.
    ///
    /// When the conflict policy selects a write to a `UserDefaults` or `NSUbiquitousKeyValueStore` destination, the
    /// destination entry is removed only when the destination key's top-level encoding is `nil` and the value written
    /// is `nil` at an actual `Optional` layer, including `.some(nil)`. The built-in optional representation encodes its
    /// own `.none` as `nil` and delegates `.some` to its base representation. A value that is not `nil` at an
    /// `Optional` layer but whose top-level encoding is `nil` fails the item at
    /// ``PersistentKeyMigrationReport/FailureStage/prepare`` with ``PersistentKeyValueConversionError/encodingFailed``
    /// and writes neither entry, while the other items in the batch proceed independently. A custom optional
    /// representation that encodes `nil` as an object, such as a marker string, writes that object, so a `nil` value
    /// does not always remove the entry. A move item can fail at a stage after its destination write or source removal.
    ///
    /// `destination` can be this store when the items' source identifiers are unique, their destination identifiers are
    /// unique, and the two sets are disjoint. A same-store move renames keys within the store.
    ///
    /// Setup failures are thrown before any item runs: missing domain metadata, an item that maps a key to itself
    /// within one store, duplicate source or destination key identifiers, a destination that is another item's source
    /// within one store, reserved completion-marker keys, key identifiers that exceed a store's limit, an empty
    /// migration identifier, or an overlapping in-process migration of the same keys or marker. Errors thrown by a
    /// store's ``PersistentKeyValueStore/migrationEndpoint`` or by reading the completion marker propagate unchanged.
    ///
    /// Per-item failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the remaining items continue,
    /// and the report is not discardable: inspect it or call ``PersistentKeyMigrationReport/throwIfIncomplete()``.
    /// On a failure before the destination write, including a transform failure, the migration writes to neither
    /// store. Migrations do not roll back completed items, and a move that fails during
    /// ``PersistentKeyMigrationReport/FailureStage/cleanup`` does not roll back its destination write (though another
    /// writer or observer may have modified or removed the value in either store). An empty batch is valid; with
    /// completion tracking, it records the marker.
    ///
    /// The move releases its references to the encoded value and to a replaced destination value before verifying the
    /// write, and to the removed source value before verifying the removal. Under
    /// ``PersistentKeyMoveConflictPolicy/keepBoth``, it releases the source value before verifying the kept
    /// destination value. After removing the source, the move checks that the destination is unchanged and then that
    /// the source is still absent, because observers notified of the removal, the removed value's `deinit`, or the
    /// destination value's code run by that comparison can change either store. Verification guards against the
    /// changes it can observe, including those these releases cause, but code that writes to a migrating store as a
    /// side effect of reading, encoding, or deallocating a value, such as a getter, `deinit`, allocator callback, or
    /// observer, is an uncoordinated writer. Coordinate such writers before migrating, as with other writers;
    /// otherwise, behavior is unspecified. On `UserDefaults` and `NSUbiquitousKeyValueStore`, the check of the source
    /// and its removal are separate calls, so a write between them is removed even when the move reports
    /// ``PersistentKeyMigrationReport/Status/moved``.
    ///
    /// Local completion does not guarantee disk durability or iCloud delivery, and removing a key from
    /// `NSUbiquitousKeyValueStore` deletes it across the user's devices. A move posts
    /// `NSUbiquitousKeyValueStore.didChangeInternallyNotification` for each `NSUbiquitousKeyValueStore` key
    /// it writes or removes.
    ///
    /// - Parameter items: The items to move, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values for destination keys in `destination`.
    /// - Parameter tracking: Whether to check and record a completion marker for this migration.
    /// - Returns: A report with one outcome per item in `items`, or no outcomes if completion was already recorded.
    public func move<Destination>(
        items: [PersistentKeyMigrationItem],
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        let sourceEndpoint = try migrationEndpoint
        let destinationEndpoint = try destination.migrationEndpoint
        return try sourceEndpoint.backend.execute(
            items,
            destination: destinationEndpoint.backend,
            operation: .move(policy),
            tracking: tracking
        )
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension PersistentKeyValueMigrationBackend {
    // MARK: Fileprivate Instance Interface

    fileprivate func execute<Destination>(
        _ items: [PersistentKeyMigrationItem],
        destination: Destination,
        operation: PersistentKeyMigrationOperation,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueMigrationBackend {
        let recorder: (id: String, backend: any PersistentKeyValueMigrationBackend)?
        switch tracking.mode {
        case .once(let id, let store?):
            recorder = (id, try store.migrationEndpoint.backend)
        case .once(let id, nil):
            recorder = (id, destination)
        case .untracked:
            recorder = nil
        }

        var identities = [migrationIdentity, destination.migrationIdentity]
        if let recorder {
            identities.append(recorder.backend.migrationIdentity)
        }

        guard
            identities.allSatisfy({
                !$0.namespace.isEmpty && !$0.identifier.isEmpty
            })
        else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        let mappings = items.map(\.mapping)
        let isSameStore = migrationIdentity == destination.migrationIdentity
        // Key identity is the store's own: Foundation stores keep literally different spellings apart, while the
        // in-memory store treats canonically equivalent spellings as one key.
        if isSameStore,
            mappings.contains(where: {
                migrationKeyIdentity($0.sourceKeyID) == migrationKeyIdentity($0.destinationKeyID)
            })
        {
            throw PersistentKeyMigrationError.sameStore
        }

        // `hasPrefix` compares characters, so a combining mark that joins the prefix's final `_` would hide the prefix.
        // Comparing code units of the NFC form also rejects canonically equivalent spellings of the prefix, such as one
        // with KELVIN SIGN for `K`, which the in-memory store treats as a marker's key.
        let markerPrefix = PersistentKeyMigrationTracking.completionMarkerPrefix.utf16
        var sourceIDs = Set<PersistentKeyMigrationKeyIdentity>()
        var destinationIDs = Set<PersistentKeyMigrationKeyIdentity>()
        for mapping in mappings {
            let sourceID = mapping.sourceKeyID
            let destinationID = mapping.destinationKeyID
            for id in [sourceID, destinationID] {
                guard !id.precomposedStringWithCanonicalMapping.utf16.starts(with: markerPrefix) else {
                    throw PersistentKeyMigrationError.reservedKey(id)
                }
            }

            guard sourceIDs.insert(migrationKeyIdentity(sourceID)).inserted else {
                throw PersistentKeyMigrationError.duplicateKey(sourceID)
            }

            guard destinationIDs.insert(destination.migrationKeyIdentity(destinationID)).inserted else {
                throw PersistentKeyMigrationError.duplicateKey(destinationID)
            }

            guard !migrationKeyIDExceedsLimit(sourceID) else {
                throw PersistentKeyMigrationError.keyIdentifierTooLong(sourceID)
            }

            guard !destination.migrationKeyIDExceedsLimit(destinationID) else {
                throw PersistentKeyMigrationError.keyIdentifierTooLong(destinationID)
            }
        }

        // No item maps a key to itself within one store, so a destination that matches a source is another item's.
        if isSameStore,
            let overlap = mappings.first(where: {
                sourceIDs.contains(migrationKeyIdentity($0.destinationKeyID))
            })
        {
            throw PersistentKeyMigrationError.overlappingKeys(overlap.destinationKeyID)
        }

        let tracked: (marker: PersistentKey<Bool>, recorder: any PersistentKeyValueMigrationBackend)?
        if let recorder {
            guard !recorder.id.isEmpty else {
                throw PersistentKeyMigrationError.invalidMigrationIdentifier
            }

            let marker = PersistentKey<Bool>.isMigrationCompleted(id: recorder.id)
            guard !recorder.backend.migrationKeyIDExceedsLimit(marker.id) else {
                throw PersistentKeyMigrationError.keyIdentifierTooLong(marker.id)
            }

            tracked = (marker, recorder.backend)
        } else {
            tracked = nil
        }

        var resources = Set(
            mappings.map {
                PersistentKeyMigrationRegistry.Resource(
                    identity: migrationIdentity,
                    key: migrationKeyIdentity($0.sourceKeyID)
                )
            }
        )
        resources.formUnion(
            mappings.map {
                PersistentKeyMigrationRegistry.Resource(
                    identity: destination.migrationIdentity,
                    key: destination.migrationKeyIdentity($0.destinationKeyID)
                )
            }
        )
        if let tracked {
            resources.insert(
                PersistentKeyMigrationRegistry.Resource(
                    identity: tracked.recorder.migrationIdentity,
                    key: tracked.recorder.migrationKeyIdentity(tracked.marker.id)
                )
            )
        }

        guard PersistentKeyMigrationRegistry.shared.claim(resources) else {
            throw PersistentKeyMigrationError.overlappingMigration
        }

        defer {
            PersistentKeyMigrationRegistry.shared.release(resources)
        }

        if let tracked {
            return try executeTracked(
                mappings,
                destination: destination,
                operation: operation,
                marker: tracked.marker,
                recorder: tracked.recorder
            )
        }

        return PersistentKeyMigrationReport(
            outcomes: migrate(mappings, destination: destination, operation: operation),
            completion: .untracked
        )
    }

    // MARK: Private Instance Interface

    private func executeTracked<Destination, Recorder>(
        _ mappings: [any PersistentKeyMigrationMappingProtocol],
        destination: Destination,
        operation: PersistentKeyMigrationOperation,
        marker: PersistentKey<Bool>,
        recorder: Recorder
    ) throws -> PersistentKeyMigrationReport
    where
        Destination: PersistentKeyValueMigrationBackend,
        Recorder: PersistentKeyValueMigrationBackend
    {
        let markerSnapshot = try recorder.migrationSnapshot(for: marker.id)
        if let markerSnapshot {
            do {
                if try recorder.migrationValue(for: marker, in: markerSnapshot) {
                    return PersistentKeyMigrationReport(outcomes: [], completion: .alreadyRecorded)
                }
            } catch {
                throw PersistentKeyMigrationError.invalidCompletionRecord
            }
        }

        let outcomes = migrate(mappings, destination: destination, operation: operation)
        guard
            !outcomes.contains(where: {
                $0.error != nil
            })
        else {
            return PersistentKeyMigrationReport(outcomes: outcomes, completion: .notRecorded)
        }

        do {
            let write = try recorder.prepareMigrationWrite(true, for: marker)
            let committedSnapshot = try recorder.commitMigrationWrite(write, replacing: markerSnapshot)
            // The snapshot can hold the last reference to the replaced marker, whose `deinit` can change the marker, so
            // it is released before the new marker is verified.
            _ = consume markerSnapshot
            guard let committedSnapshot,
                try recorder.migrationSnapshotIsCurrent(committedSnapshot, for: marker.id),
                try recorder.migrationValue(for: marker, in: committedSnapshot)
            else {
                throw PersistentKeyMigrationError.writeVerificationFailed
            }

            return PersistentKeyMigrationReport(outcomes: outcomes, completion: .recorded)
        } catch {
            return PersistentKeyMigrationReport(outcomes: outcomes, completionError: error)
        }
    }

    private func migrate<Destination>(
        _ mappings: [any PersistentKeyMigrationMappingProtocol],
        destination: Destination,
        operation: PersistentKeyMigrationOperation
    ) -> [PersistentKeyMigrationReport.Outcome]
    where Destination: PersistentKeyValueMigrationBackend {
        mappings.map {
            $0.migrate(from: self, to: destination, operation: operation)
        }
    }
}
