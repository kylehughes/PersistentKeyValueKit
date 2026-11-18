import Foundation

@testable import PersistentKeyValueKit

final class MigrationFaultStore {
    let base: InMemoryPersistentKeyValueStore
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity
    private(set) var accessCount = 0
    var commitHook: ((String) -> Void)?
    var failure: Point?
    var failureKey: String?
    var hook: (() -> Void)?
    var keyedHook: ((String) -> Void)?
    var keyIDLimit: Int?
    var malformedCompletionRecord = false

    // MARK: Internal Initialization

    init(
        _ base: InMemoryPersistentKeyValueStore = .init(),
        identifier: String = UUID().uuidString
    ) {
        self.base = base
        migrationIdentity = .init(namespace: "Fault", identifier: identifier)
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension MigrationFaultStore: PersistentKeyValueMigrationBackend {
    typealias MigrationSnapshot = InMemoryPersistentKeyValueStore.MigrationSnapshot
    typealias MigrationWrite = InMemoryPersistentKeyValueStore.MigrationWrite

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        if failure == .commit && (failureKey == nil || failureKey == write.keyID) {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        hook?()
        keyedHook?(write.keyID)
        commitHook?(write.keyID)

        if let snapshot, !(try migrationSnapshotIsCurrent(snapshot, for: write.keyID)) {
            throw PersistentKeyMigrationError.destinationChanged
        }

        let baseSnapshot = snapshot.map {
            InMemoryPersistentKeyValueStore.MigrationSnapshot(
                identity: base.migrationIdentity,
                keyID: $0.keyID,
                revision: $0.revision,
                object: $0.object
            )
        }
        let result = try base.commitMigrationWrite(
            .init(identity: base.migrationIdentity, keyID: write.keyID, object: write.object),
            replacing: baseSnapshot
        )

        return result.map {
            .init(
                identity: migrationIdentity,
                keyID: write.keyID,
                revision: $0.revision,
                object: $0.object
            )
        }
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        keyIDLimit.map {
            keyID.count > $0
        } ?? false
    }

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        base.migrationKeyIdentity(keyID)
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        accessCount += 1

        if failure == .snapshot && (failureKey == nil || failureKey == keyID) {
            throw InjectedFailure()
        }

        hook?()
        keyedHook?(keyID)

        return try base.migrationSnapshot(for: keyID).map {
            .init(identity: migrationIdentity, keyID: keyID, revision: $0.revision, object: $0.object)
        }
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        guard let current = try migrationSnapshot(for: keyID) else {
            return false
        }

        return current.revision == snapshot.revision
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        if malformedCompletionRecord && key.id.hasPrefix("PersistentKeyValueKit_MigrationCompleted_") {
            throw PersistentKeyMigrationError.invalidCompletionRecord
        }

        return try base.migrationValue(
            for: key,
            in: .init(
                identity: base.migrationIdentity,
                keyID: snapshot.keyID,
                revision: snapshot.revision,
                object: snapshot.object
            )
        )
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        if failure == .prepare && (failureKey == nil || failureKey == key.id) {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        let prepared = try base.prepareMigrationWrite(value, for: key)

        return .init(identity: migrationIdentity, keyID: key.id, object: prepared.object)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        if failure == .remove && (failureKey == nil || failureKey == keyID) {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }

        try base.removeMigrationValue(
            for: keyID,
            matching: .init(
                identity: base.migrationIdentity,
                keyID: keyID,
                revision: snapshot.revision,
                object: snapshot.object
            )
        )
    }
}
// MARK: - PersistentKeyValueStore Extension

extension MigrationFaultStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
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

// MARK: - InjectedFailure Definition

extension MigrationFaultStore {
    struct InjectedFailure: Error {}
}

// MARK: - Point Definition

extension MigrationFaultStore {
    enum Point {
        case snapshot
        case prepare
        case commit
        case remove
    }
}
