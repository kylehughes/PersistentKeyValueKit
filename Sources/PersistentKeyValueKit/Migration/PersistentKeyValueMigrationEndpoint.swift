import Foundation

// MARK: - Public Interface

/// An opaque migration capability for a ``PersistentKeyValueStore``.
///
/// Built-in stores (`UserDefaults`, `NSUbiquitousKeyValueStore`, and ``InMemoryPersistentKeyValueStore``) provide an
/// endpoint through ``PersistentKeyValueStore/migrationEndpoint``. Custom store wrappers can support migration by
/// forwarding their backing store's endpoint (`try base.migrationEndpoint`) without exposing backend identity or
/// snapshot mechanics.
///
/// Forwarding an endpoint delegates migration directly to the backing store; migration does not route individual reads,
/// writes, or removals through a wrapper's ``PersistentKeyValueStore/get(_:)``,
/// ``PersistentKeyValueStore/set(_:to:)``, or ``PersistentKeyValueStore/remove(_:)`` methods.
public struct PersistentKeyValueMigrationEndpoint {
    let backend: any PersistentKeyValueMigrationBackend

    init(backend: any PersistentKeyValueMigrationBackend) {
        self.backend = backend
    }
}

// MARK: - Internal Interface

/// The backend contract used by the migration engine.
///
/// This is intentionally internal: the public API describes what clients can do, while the library retains knowledge
/// of the storage implementations and their consistency rules.
protocol PersistentKeyValueMigrationBackend {
    associatedtype MigrationSnapshot
    associatedtype MigrationWrite

    var migrationIdentity: PersistentKeyValueMigrationStoreIdentity { get }

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot?

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot?

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value
    where Key: PersistentKeyProtocol

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite
    where Key: PersistentKeyProtocol

    func removeMigrationValue(
        for keyID: String,
        matching snapshot: MigrationSnapshot
    ) throws
}

// MARK: - Internal Identity

struct PersistentKeyValueMigrationStoreIdentity: Hashable, Sendable {
    let identifier: String
    let namespace: String

    init(namespace: String, identifier: String) {
        self.namespace = namespace
        self.identifier = identifier
    }
}
