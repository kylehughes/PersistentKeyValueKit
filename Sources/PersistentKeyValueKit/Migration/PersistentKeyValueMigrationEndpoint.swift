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

    /// Whether `keyID` exceeds this store's key identifier limit. The engine checks every identifier before mutation.
    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool

    /// Returns the identity under which this store keeps the value for `keyID`.
    ///
    /// Two identifiers name the same stored value in this store exactly when their identities are equal.
    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity

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

/// The identity a store gives a key identifier.
///
/// Foundation stores compare key identifiers by their UTF-16 code units, so canonically equivalent spellings, such as
/// composed and decomposed "café", name different keys. A store keyed by Swift `String` treats them as one key.
struct PersistentKeyMigrationKeyIdentity: Hashable {
    private let value: AnyHashable

    // MARK: Private Initialization

    private init(value: AnyHashable) {
        self.value = value
    }

    // MARK: Internal Static Interface

    /// An identity that equals another exactly when the identifiers are canonically equivalent, as Swift `String`
    /// equality defines.
    static func canonical(_ keyID: String) -> Self {
        Self(value: keyID)
    }

    /// An identity that equals another exactly when the identifiers have the same UTF-16 code units.
    static func literal(_ keyID: String) -> Self {
        Self(value: LiteralKeyID.codeUnits(of: keyID))
    }
}


struct PersistentKeyValueMigrationStoreIdentity: Hashable, Sendable {
    let identifier: String
    let namespace: String

    init(namespace: String, identifier: String) {
        self.namespace = namespace
        self.identifier = identifier
    }
}
