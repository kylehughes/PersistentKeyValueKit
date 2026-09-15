import Foundation

/// Synchronizes in-process migration ownership; store operations never run under this lock.
private final class PersistentKeyMigrationRegistry: @unchecked Sendable {
    struct Resource: Hashable {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
    }
    static let shared = PersistentKeyMigrationRegistry()
    private let lock = NSLock()
    private var resources = Set<Resource>()
    private init() {}
    func claim(_ values: Set<Resource>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard values.isDisjoint(with: resources) else { return false }
        resources.formUnion(values)
        return true
    }
    func release(_ values: Set<Resource>) {
        lock.lock()
        resources.subtract(values)
        lock.unlock()
    }
}

fileprivate enum PersistentKeyMigrationOperation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)
}

extension PersistentKeyValueMigrationStore {
    /// Copies one typed key to another migration-capable store.
    public func copy<Key, Destination>(
        _ key: Key, to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueMigrationStore {
        try migrationEndpoint.backend.execute(
            [key], destination: destination.migrationEndpoint.backend,
            operation: PersistentKeyMigrationOperation.copy(policy), completion: completion)
    }

    /// Copies keys in input order, returning one outcome per key.
    public func copy<Destination>(
        _ keys: [any PersistentKeyProtocol], to destination: Destination,
        onConflict policy: PersistentKeyCopyConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport where Destination: PersistentKeyValueMigrationStore {
        try migrationEndpoint.backend.execute(
            keys, destination: destination.migrationEndpoint.backend, operation: PersistentKeyMigrationOperation.copy(policy),
            completion: completion)
    }

    /// Moves one typed key, removing the source after verified transfer or according to the selected conflict policy.
    ///
    /// `keepDestinationAndRemoveSource` can remove the source without writing a destination value. If source cleanup
    /// fails after a transfer, the copied destination value remains in place.
    public func move<Key, Destination>(
        _ key: Key, to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueMigrationStore {
        try migrationEndpoint.backend.execute(
            [key], destination: destination.migrationEndpoint.backend,
            operation: PersistentKeyMigrationOperation.move(policy), completion: completion)
    }

    /// Moves keys in input order, returning one outcome per key.
    ///
    /// Setup failures are thrown before mutation. Per-key conversion, write, and cleanup failures are returned in the
    /// report, and a partial batch is not rolled back.
    public func move<Destination>(
        _ keys: [any PersistentKeyProtocol], to destination: Destination,
        onConflict policy: PersistentKeyMoveConflictPolicy,
        completion: PersistentKeyMigrationCompletionPolicy = .untracked
    ) throws -> PersistentKeyMigrationReport where Destination: PersistentKeyValueMigrationStore {
        try migrationEndpoint.backend.execute(
            keys, destination: destination.migrationEndpoint.backend, operation: PersistentKeyMigrationOperation.move(policy),
            completion: completion)
    }

}

extension PersistentKeyValueMigrationBackend {
    fileprivate func execute<Destination>(
        _ keys: [any PersistentKeyProtocol], destination: Destination, operation: PersistentKeyMigrationOperation,
        completion: PersistentKeyMigrationCompletionPolicy
    ) throws -> PersistentKeyMigrationReport where Destination: PersistentKeyValueMigrationBackend {
        let recorderEndpoint: PersistentKeyValueMigrationEndpoint?
        switch completion {
        case .untracked:
            recorderEndpoint = nil
        case .once(_, let recorder):
            recorderEndpoint = recorder.migrationEndpoint
        }
        guard !migrationIdentity.namespace.isEmpty, !migrationIdentity.identifier.isEmpty,
            !destination.migrationIdentity.namespace.isEmpty, !destination.migrationIdentity.identifier.isEmpty
        else { throw PersistentKeyMigrationError.invalidStoreIdentifier }
        guard migrationIdentity != destination.migrationIdentity else { throw PersistentKeyMigrationError.sameStore }
        var ids = Set<String>()
        for key in keys {
            guard ids.insert(key.id).inserted else { throw PersistentKeyMigrationError.duplicateKey(key.id) }
            if key.id.hasPrefix("PersistentKeyValueKit.MigrationCompleted.") {
                throw PersistentKeyMigrationError.reservedKey(key.id)
            }
        }
        let marker: PersistentKey<Bool>?
        switch completion {
        case .untracked: marker = nil
        case .once(let id, _):
            guard !id.isEmpty else { throw PersistentKeyMigrationError.invalidMigrationIdentifier }
            guard let recorderBackend = recorderEndpoint?.backend,
                !recorderBackend.migrationIdentity.namespace.isEmpty,
                !recorderBackend.migrationIdentity.identifier.isEmpty
            else { throw PersistentKeyMigrationError.invalidStoreIdentifier }
            marker = .isMigrationCompleted(id: id)
        }
        var resources = Set(
            keys.map { PersistentKeyMigrationRegistry.Resource(identity: migrationIdentity, keyID: $0.id) })
        resources.formUnion(
            keys.map { PersistentKeyMigrationRegistry.Resource(identity: destination.migrationIdentity, keyID: $0.id) })
        if let marker, let recorderBackend = recorderEndpoint?.backend {
            resources.insert(
                PersistentKeyMigrationRegistry.Resource(identity: recorderBackend.migrationIdentity, keyID: marker.id))
        }
        guard PersistentKeyMigrationRegistry.shared.claim(resources) else {
            throw PersistentKeyMigrationError.overlappingMigration
        }
        defer { PersistentKeyMigrationRegistry.shared.release(resources) }

        if case .once(let id, _) = completion, let recorderBackend = recorderEndpoint?.backend {
            return try executeTracked(
                keys, destination: destination, operation: operation, id: id, recorder: recorderBackend)
        }
        return executeUntracked(keys, destination: destination, operation: operation)
    }

    private func executeUntracked<Destination>(
        _ keys: [any PersistentKeyProtocol], destination: Destination, operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport where Destination: PersistentKeyValueMigrationBackend {
        var outcomes: [PersistentKeyMigrationReport.Outcome] = []
        for key in keys { outcomes.append(migrate(key, destination: destination, operation: operation)) }
        return PersistentKeyMigrationReport(outcomes: outcomes, completion: .untracked)
    }

    private func executeTracked<Destination, Recorder>(
        _ keys: [any PersistentKeyProtocol], destination: Destination, operation: PersistentKeyMigrationOperation,
        id: String, recorder: Recorder
    ) throws -> PersistentKeyMigrationReport
    where Destination: PersistentKeyValueMigrationBackend, Recorder: PersistentKeyValueMigrationBackend {
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: id)
        let markerSnapshot: Recorder.MigrationSnapshot?
        markerSnapshot = try recorder.migrationSnapshot(for: marker.id)
        if let markerSnapshot {
            do {
                if try recorder.migrationValue(for: marker, in: markerSnapshot) {
                    return PersistentKeyMigrationReport(outcomes: [], completion: .alreadyRecorded)
                }
            } catch { throw PersistentKeyMigrationError.invalidCompletionRecord }
        }
        let outcomes = keys.map { migrate($0, destination: destination, operation: operation) }
        guard
            !outcomes.contains(where: {
                if case .failed = $0.status { return true }
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
            else { throw PersistentKeyMigrationError.writeVerificationFailed }
            return PersistentKeyMigrationReport(outcomes: outcomes, completion: .recorded)
        } catch { return PersistentKeyMigrationReport(outcomes: outcomes, completion: .failed(error)) }
    }

    private func migrate<Key, Destination>(
        _ key: Key, destination: Destination, operation: PersistentKeyMigrationOperation
    ) -> PersistentKeyMigrationReport.Outcome
    where Key: PersistentKeyProtocol, Destination: PersistentKeyValueMigrationBackend {
        let id = key.id
        guard key.isMigrationEnabled else { return .init(keyID: id, status: .keyDisabled) }
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
                if destinationSnapshot != nil, policy == .keepBoth { return .init(keyID: id, status: .keptDestination) }
                if destinationSnapshot != nil, policy == .keepDestinationAndRemoveSource {
                    stage = .cleanup
                    guard let destinationSnapshot,
                        try destination.migrationSnapshotIsCurrent(destinationSnapshot, for: id)
                    else { throw PersistentKeyMigrationError.destinationChanged }
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
