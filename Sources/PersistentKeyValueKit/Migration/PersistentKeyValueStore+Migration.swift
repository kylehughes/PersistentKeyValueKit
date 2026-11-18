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
            switch operation {
            case .copy(let policy):
                if destinationSnapshot != nil, policy == .keepDestination {
                    return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .keptDestination)
                }
            case .move(let policy):
                if destinationSnapshot != nil, policy == .keepBoth {
                    return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .keptDestination)
                }

                if destinationSnapshot != nil, policy == .keepDestinationAndRemoveSource {
                    // Keeping the destination is verified like a write, so a change found here, before the source is
                    // removed, fails at the same stage as a change found while writing.
                    stage = .write
                    guard let destinationSnapshot,
                        try destinationStore.migrationSnapshotIsCurrent(destinationSnapshot, for: destinationID)
                    else {
                        throw PersistentKeyMigrationError.destinationChanged
                    }

                    stage = .cleanup
                    guard try sourceStore.migrationSnapshotIsCurrent(sourceSnapshot, for: sourceID) else {
                        throw PersistentKeyMigrationError.sourceChanged
                    }

                    try sourceStore.removeMigrationValue(for: sourceID, matching: sourceSnapshot)
                    // Removal can notify observers synchronously, and they can change the destination.
                    guard try destinationStore.migrationSnapshotIsCurrent(destinationSnapshot, for: destinationID)
                    else {
                        throw PersistentKeyMigrationError.destinationChanged
                    }

                    return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .discardedSource)
                }
            }

            stage = .decode
            let value = try sourceStore.migrationValue(for: source, in: sourceSnapshot)
            stage = .transform
            let destinationValue = try transform(value)
            stage = .prepare
            let write = try destinationStore.prepareMigrationWrite(destinationValue, for: destination)
            stage = .write
            let committedSnapshot = try Self.commit(
                write,
                replacing: destinationSnapshot,
                in: destinationStore,
                for: destinationID
            )

            if case .move = operation {
                stage = .cleanup
                guard try sourceStore.migrationSnapshotIsCurrent(sourceSnapshot, for: sourceID) else {
                    throw PersistentKeyMigrationError.sourceChanged
                }

                try sourceStore.removeMigrationValue(for: sourceID, matching: sourceSnapshot)
                // Removal can notify observers synchronously, and they can change the destination.
                guard try Self.isCommitted(committedSnapshot, in: destinationStore, for: destinationID) else {
                    throw PersistentKeyMigrationError.destinationChanged
                }

                return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .moved)
            }

            return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, status: .copied)
        } catch {
            return .init(sourceKeyID: sourceID, destinationKeyID: destinationID, failedAt: stage, error: error)
        }
    }

    // MARK: Private Static Interface

    /// Commits `write` in place of `snapshot`, throwing ``PersistentKeyMigrationError/writeVerificationFailed`` unless
    /// `store` then holds the committed value.
    private static func commit<Store>(
        _ write: Store.MigrationWrite,
        replacing snapshot: Store.MigrationSnapshot?,
        in store: Store,
        for keyID: String
    ) throws -> Store.MigrationSnapshot? where Store: PersistentKeyValueMigrationBackend {
        let committedSnapshot = try store.commitMigrationWrite(write, replacing: snapshot)
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
    /// added suites, and key default values are neither copied nor treated as destination conflicts.
    ///
    /// `destination` can be this store when every item maps its source key to a different key identifier.
    ///
    /// Setup failures are thrown before any key is read or modified: missing domain metadata, an item that maps a key
    /// to itself within one store, duplicate source or destination key identifiers, a destination that is another
    /// item's source within one store, reserved completion-marker keys, key identifiers that exceed a store's limit, an
    /// empty migration identifier, or an overlapping in-process migration of the same keys or marker. Errors thrown by
    /// a store's ``PersistentKeyValueStore/migrationEndpoint`` or by reading the completion marker propagate unchanged.
    ///
    /// Per-item failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the remaining items continue.
    /// Completed writes are not rolled back if a later item fails. An empty batch is valid; with completion tracking,
    /// it records the marker.
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
    /// in place. Only values persisted in each store's own domain participate; registered defaults, launch arguments,
    /// added suites, and key default values are neither moved nor treated as destination conflicts.
    ///
    /// `destination` can be this store when every item maps its source key to a different key identifier, which
    /// renames keys within the store.
    ///
    /// Setup failures are thrown before any key is read or modified: missing domain metadata, an item that maps a key
    /// to itself within one store, duplicate source or destination key identifiers, a destination that is another
    /// item's source within one store, reserved completion-marker keys, key identifiers that exceed a store's limit, an
    /// empty migration identifier, or an overlapping in-process migration of the same keys or marker. Errors thrown by
    /// a store's ``PersistentKeyValueStore/migrationEndpoint`` or by reading the completion marker propagate unchanged.
    ///
    /// Per-item failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the remaining items continue.
    /// On a failure before the destination write, including a transform failure, the migration writes to neither
    /// store. Migrations do not roll back completed items, and a move that fails during
    /// ``PersistentKeyMigrationReport/FailureStage/cleanup`` does not roll back its destination write (though another
    /// writer or observer may have modified or removed the value in either store). After removing the source, the move
    /// checks the destination again, because observers notified of the removal can change it. An empty batch is valid;
    /// with completion tracking, it records the marker.
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

        let markerPrefix = PersistentKeyMigrationTracking.completionMarkerPrefix
        var sourceIDs = Set<PersistentKeyMigrationKeyIdentity>()
        var destinationIDs = Set<PersistentKeyMigrationKeyIdentity>()
        for mapping in mappings {
            let sourceID = mapping.sourceKeyID
            let destinationID = mapping.destinationKeyID
            for id in [sourceID, destinationID] where id.hasPrefix(markerPrefix) {
                throw PersistentKeyMigrationError.reservedKey(id)
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
            guard let committedSnapshot = try recorder.commitMigrationWrite(write, replacing: markerSnapshot),
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
