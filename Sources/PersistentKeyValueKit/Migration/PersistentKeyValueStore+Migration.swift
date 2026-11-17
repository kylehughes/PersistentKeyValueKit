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
        let keyID: String
    }
}

// MARK: - Migration Operation

fileprivate enum PersistentKeyMigrationOperation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)
}

// MARK: - PersistentKeyValueStore Extension

extension PersistentKeyValueStore {
    // MARK: Public Instance Interface

    /// Copies a persisted value for one key from this store to another store.
    ///
    /// Only a value persisted in this store's own domain is copied; registered defaults, launch arguments, added
    /// suites, and the key's ``PersistentKeyProtocol/defaultValue`` do not participate and do not count as destination
    /// conflicts. Conversion between storage formats uses the key's ``PersistentKeyProtocol/representation``.
    ///
    /// Setup failures (such as missing domain metadata or migrating a store to itself) are thrown before mutation.
    /// Conversion or write failures for `key` are returned in the report's ``PersistentKeyMigrationReport/outcomes``.
    ///
    /// - Parameter key: The key to copy.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value in `destination`.
    /// - Parameter completion: Optional once-only completion tracking for this migration. Defaults to `.untracked`.
    /// - Returns: A report containing the key's outcome and the completion-tracking status.
    public func copy<Key, Destination>(
        _ key: Key,
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueStore {
        try copy([key], to: destination, onConflict: policy, completion: completion)
    }

    /// Copies persisted values for the given keys to another store in input order.
    ///
    /// A batch can contain keys with different value types. Only values persisted in each store's own domain
    /// participate; registered defaults, launch arguments, added suites, and key default values are ignored. Each
    /// value is decoded from this store and encoded for `destination` using its key's
    /// ``PersistentKeyProtocol/representation``.
    ///
    /// Setup failures (such as missing domain metadata, migrating a store to itself, duplicate key identifiers,
    /// reserved completion-marker keys, or overlapping in-process migrations for the same store and key) are thrown
    /// before any key is modified. Per-key failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the
    /// remaining keys in `keys` continue. Completed writes are not rolled back if a later key fails.
    ///
    /// - Parameter keys: The keys to copy, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values in `destination`.
    /// - Parameter completion: Optional once-only completion tracking for this migration. Defaults to `.untracked`.
    /// - Returns: A report with one outcome per key in `keys`, or no outcomes if completion was already recorded.
    public func copy<Destination>(
        _ keys: [any PersistentKeyProtocol],
        to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        let sourceEndpoint = try migrationEndpoint
        let destinationEndpoint = try destination.migrationEndpoint
        return try sourceEndpoint.backend.execute(
            keys,
            destination: destinationEndpoint.backend,
            operation: PersistentKeyMigrationOperation.copy(policy),
            completion: completion
        )
    }

    /// Moves a persisted value for one key from this store to another store, removing the source value after a
    /// verified transfer or when ``PersistentKeyMoveConflictPolicy/keepDestinationAndRemoveSource`` resolves a
    /// conflict.
    ///
    /// Only a value persisted in this store's own domain is moved; registered defaults, launch arguments, added
    /// suites, and the key's ``PersistentKeyProtocol/defaultValue`` do not participate and do not count as destination
    /// conflicts.
    ///
    /// Setup failures are thrown before mutation. Per-key conversion, write, and source-cleanup failures are returned
    /// in the report. If source removal fails after the destination write succeeds, the copied value remains in
    /// `destination` and the outcome fails at ``PersistentKeyMigrationReport/FailureStage/cleanup``.
    ///
    /// - Parameter key: The key to move.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle an existing persisted value in `destination`.
    /// - Parameter completion: Optional once-only completion tracking for this migration. Defaults to `.untracked`.
    /// - Returns: A report containing the key's outcome and the completion-tracking status.
    public func move<Key, Destination>(
        _ key: Key,
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueStore {
        try move([key], to: destination, onConflict: policy, completion: completion)
    }

    /// Moves persisted values for the given keys to another store in input order.
    ///
    /// A batch can contain keys with different value types. Only values persisted in each store's own domain
    /// participate; registered defaults, launch arguments, added suites, and key default values are ignored. Each
    /// value is decoded from this store and encoded for `destination` using its key's
    /// ``PersistentKeyProtocol/representation``.
    ///
    /// Setup failures (such as missing domain metadata, migrating a store to itself, duplicate key identifiers,
    /// reserved completion-marker keys, or overlapping in-process migrations for the same store and key) are thrown
    /// before any key is modified. Per-key failures are recorded in ``PersistentKeyMigrationReport/outcomes`` while the
    /// remaining keys in `keys` continue. Migrations do not roll back completed keys, and a move that fails during
    /// ``PersistentKeyMigrationReport/FailureStage/cleanup`` leaves the copied value in `destination`.
    ///
    /// - Parameter keys: The keys to move, processed in order.
    /// - Parameter destination: The destination store.
    /// - Parameter policy: How to handle existing persisted values in `destination`.
    /// - Parameter completion: Optional once-only completion tracking for this migration. Defaults to `.untracked`.
    /// - Returns: A report with one outcome per key in `keys`, or no outcomes if completion was already recorded.
    public func move<Destination>(
        _ keys: [any PersistentKeyProtocol],
        to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueStore {
        let sourceEndpoint = try migrationEndpoint
        let destinationEndpoint = try destination.migrationEndpoint
        return try sourceEndpoint.backend.execute(
            keys,
            destination: destinationEndpoint.backend,
            operation: PersistentKeyMigrationOperation.move(policy),
            completion: completion
        )
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension PersistentKeyValueMigrationBackend {
    // MARK: Fileprivate Instance Interface

    fileprivate func execute<Destination>(
        _ keys: [any PersistentKeyProtocol],
        destination: Destination,
        operation: PersistentKeyMigrationOperation,
        completion: PersistentKeyMigrationCompletionPolicy
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueMigrationBackend {
        let recorderEndpoint: PersistentKeyValueMigrationEndpoint?
        switch completion {
        case .untracked:
            recorderEndpoint = nil
        case .once(_, let recorder):
            recorderEndpoint = try recorder.migrationEndpoint
        }

        guard !migrationIdentity.namespace.isEmpty,
            !migrationIdentity.identifier.isEmpty,
            !destination.migrationIdentity.namespace.isEmpty,
            !destination.migrationIdentity.identifier.isEmpty
        else {
            throw PersistentKeyMigrationError.invalidStoreIdentifier
        }

        guard migrationIdentity != destination.migrationIdentity else {
            throw PersistentKeyMigrationError.sameStore
        }

        var ids = Set<String>()
        for key in keys {
            guard ids.insert(key.id).inserted else {
                throw PersistentKeyMigrationError.duplicateKey(key.id)
            }

            if key.id.hasPrefix("PersistentKeyValueKit.MigrationCompleted.") {
                throw PersistentKeyMigrationError.reservedKey(key.id)
            }
        }

        let marker: PersistentKey<Bool>?
        switch completion {
        case .untracked:
            marker = nil
        case .once(let id, _):
            guard !id.isEmpty else {
                throw PersistentKeyMigrationError.invalidMigrationIdentifier
            }

            guard let recorderBackend = recorderEndpoint?.backend,
                !recorderBackend.migrationIdentity.namespace.isEmpty,
                !recorderBackend.migrationIdentity.identifier.isEmpty
            else {
                throw PersistentKeyMigrationError.invalidStoreIdentifier
            }

            marker = .isMigrationCompleted(id: id)
        }

        var resources = Set(
            keys.map {
                PersistentKeyMigrationRegistry.Resource(identity: migrationIdentity, keyID: $0.id)
            }
        )
        resources.formUnion(
            keys.map {
                PersistentKeyMigrationRegistry.Resource(identity: destination.migrationIdentity, keyID: $0.id)
            }
        )
        if let marker, let recorderBackend = recorderEndpoint?.backend {
            resources.insert(
                PersistentKeyMigrationRegistry.Resource(identity: recorderBackend.migrationIdentity, keyID: marker.id)
            )
        }

        guard PersistentKeyMigrationRegistry.shared.claim(resources) else {
            throw PersistentKeyMigrationError.overlappingMigration
        }

        defer {
            PersistentKeyMigrationRegistry.shared.release(resources)
        }

        if let marker, let recorderBackend = recorderEndpoint?.backend {
            return try executeTracked(
                keys,
                destination: destination,
                operation: operation,
                marker: marker,
                recorder: recorderBackend
            )
        }

        return executeUntracked(keys, destination: destination, operation: operation)
    }

    // MARK: Private Instance Interface

    private func executeTracked<Destination, Recorder>(
        _ keys: [any PersistentKeyProtocol],
        destination: Destination,
        operation: PersistentKeyMigrationOperation,
        marker: PersistentKey<Bool>,
        recorder: Recorder
    ) throws -> PersistentKeyMigrationReport
    where
        Destination: PersistentKeyValueMigrationBackend,
        Recorder: PersistentKeyValueMigrationBackend
    {
        let markerSnapshot: Recorder.MigrationSnapshot?
        markerSnapshot = try recorder.migrationSnapshot(for: marker.id)
        if let markerSnapshot {
            do {
                if try recorder.migrationValue(for: marker, in: markerSnapshot) {
                    return PersistentKeyMigrationReport(outcomes: [], completion: .alreadyRecorded)
                }
            } catch {
                throw PersistentKeyMigrationError.invalidCompletionRecord
            }
        }

        let outcomes = keys.map {
            migrate($0, destination: destination, operation: operation)
        }

        guard
            !outcomes.contains(where: {
                if case .failed = $0.status {
                    return true
                }

                return false
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
            return PersistentKeyMigrationReport(outcomes: outcomes, completion: .failed(error))
        }
    }

    private func executeUntracked<Destination>(
        _ keys: [any PersistentKeyProtocol],
        destination: Destination,
        operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueMigrationBackend {
        var outcomes: [PersistentKeyMigrationReport.Outcome] = []

        for key in keys {
            outcomes.append(migrate(key, destination: destination, operation: operation))
        }

        return PersistentKeyMigrationReport(outcomes: outcomes, completion: .untracked)
    }

    private func migrate<Key, Destination>(
        _ key: Key,
        destination: Destination,
        operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport.Outcome
    where
        Key: PersistentKeyProtocol,
        Destination: PersistentKeyValueMigrationBackend
    {
        let id = key.id
        guard key.isMigrationEnabled else {
            return .init(keyID: id, status: .keyDisabled)
        }

        var stage: PersistentKeyMigrationReport.FailureStage = .snapshot
        do {
            guard let sourceSnapshot = try migrationSnapshot(for: id) else {
                return .init(keyID: id, status: .sourceAbsent)
            }

            let destinationSnapshot = try destination.migrationSnapshot(for: id)
            switch operation {
            case .copy(let policy):
                if destinationSnapshot != nil, policy == .keepDestination {
                    return .init(keyID: id, status: .keptDestination)
                }
            case .move(let policy):
                if destinationSnapshot != nil, policy == .keepBoth {
                    return .init(keyID: id, status: .keptDestination)
                }

                if destinationSnapshot != nil, policy == .keepDestinationAndRemoveSource {
                    stage = .cleanup
                    guard let destinationSnapshot,
                        try destination.migrationSnapshotIsCurrent(destinationSnapshot, for: id)
                    else {
                        throw PersistentKeyMigrationError.destinationChanged
                    }

                    guard try migrationSnapshotIsCurrent(sourceSnapshot, for: id) else {
                        throw PersistentKeyMigrationError.sourceChanged
                    }

                    try removeMigrationValue(for: id, matching: sourceSnapshot)
                    return .init(keyID: id, status: .discardedSource)
                }
            }

            let value: Key.Value
            stage = .decode
            value = try migrationValue(for: key, in: sourceSnapshot)
            let write: Destination.MigrationWrite
            stage = .prepare
            write = try destination.prepareMigrationWrite(value, for: key)
            stage = .write
            let committedSnapshot = try destination.commitMigrationWrite(write, replacing: destinationSnapshot)
            if let committedSnapshot {
                guard try destination.migrationSnapshotIsCurrent(committedSnapshot, for: id) else {
                    throw PersistentKeyMigrationError.writeVerificationFailed
                }
            } else {
                guard try destination.migrationSnapshot(for: id) == nil else {
                    throw PersistentKeyMigrationError.writeVerificationFailed
                }
            }

            if case .move = operation {
                stage = .cleanup
                guard try migrationSnapshotIsCurrent(sourceSnapshot, for: id) else {
                    throw PersistentKeyMigrationError.sourceChanged
                }

                try removeMigrationValue(for: id, matching: sourceSnapshot)
                return .init(keyID: id, status: .moved)
            }

            return .init(keyID: id, status: .copied)
        } catch {
            return .init(keyID: id, status: .failed(stage: stage, error: error))
        }
    }
}
