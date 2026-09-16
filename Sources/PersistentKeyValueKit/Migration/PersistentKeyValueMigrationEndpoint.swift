import Foundation

/// An opaque capability used by the migration engine.
///
/// The endpoint keeps storage mechanics private while allowing generic client abstractions to forward migration
/// operations without knowing whether the store is backed by UserDefaults, iCloud, or memory. Forwarding an endpoint
/// forwards migration work to the backing store; it does not route individual reads or writes through a wrapper's
/// ordinary ``PersistentKeyValueStore`` methods.
public struct PersistentKeyValueMigrationEndpoint {
    let backend: any PersistentKeyValueMigrationBackend

    init(backend: any PersistentKeyValueMigrationBackend) {
        self.backend = backend
    }
}

/// The backend contract used by the migration engine.
///
/// This is intentionally internal: the public API describes what clients can do, while the library retains knowledge
/// of the storage implementations and their consistency rules.
protocol PersistentKeyValueMigrationBackend {
    associatedtype MigrationSnapshot
    associatedtype MigrationWrite

    var migrationIdentity: PersistentKeyValueMigrationStoreIdentity { get }
    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot?
    func migrationValue<Key>(for key: Key, in snapshot: MigrationSnapshot) throws -> Key.Value
    where Key: PersistentKeyProtocol
    func prepareMigrationWrite<Key>(_ value: Key.Value, for key: Key) throws -> MigrationWrite
    where Key: PersistentKeyProtocol
    func commitMigrationWrite(_ write: MigrationWrite, replacing snapshot: MigrationSnapshot?) throws
        -> MigrationSnapshot?
    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws
    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool
}

struct PersistentKeyValueMigrationStoreIdentity: Hashable, Sendable {
    let namespace: String
    let identifier: String

    init(namespace: String, identifier: String) {
        self.namespace = namespace
        self.identifier = identifier
    }
}
