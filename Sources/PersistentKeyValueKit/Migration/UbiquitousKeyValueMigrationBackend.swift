import Foundation

/// The migration backend for an iCloud key-value store.
///
/// The wrapped store and identity are immutable after initialization. Subclasses and test doubles must preserve the
/// thread-safety expected from NSUbiquitousKeyValueStore. A successful local write does not establish cloud delivery
/// or durability.
@available(watchOS 9.0, *)
final class UbiquitousKeyValueMigrationBackend: @unchecked Sendable {
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity

    /// The underlying store for ordinary Foundation access.
    let ubiquitousStore: NSUbiquitousKeyValueStore

    // MARK: Internal Initialization

    /// Creates a backend for the supplied iCloud key-value store.
    ///
    /// Instances use the canonical ubiquitous-store identity because Foundation instances share one backing store.
    init(_ store: NSUbiquitousKeyValueStore = .default) {
        ubiquitousStore = store
        migrationIdentity = PersistentKeyValueMigrationStoreIdentity(
            namespace: "NSUbiquitousKeyValueStore",
            identifier: "default"
        )
    }

    internal init(store: NSUbiquitousKeyValueStore, identity: PersistentKeyValueMigrationStoreIdentity) {
        ubiquitousStore = store
        migrationIdentity = identity
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend: PersistentKeyValueMigrationBackend {
    // MARK: Internal Instance Interface

    var migrationHandle: ObjectIdentifier {
        ObjectIdentifier(ubiquitousStore)
    }

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        guard write.identity == migrationIdentity else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        if let snapshot, !(try migrationSnapshotIsCurrent(snapshot, for: write.keyID)) {
            throw PersistentKeyMigrationError.destinationChanged
        }

        if snapshot == nil, try migrationSnapshot(for: write.keyID) != nil {
            throw PersistentKeyMigrationError.destinationChanged
        }

        if let object = write.object {
            ubiquitousStore.set(object, forKey: write.keyID)
        } else {
            ubiquitousStore.removeObject(forKey: write.keyID)
        }

        NSUbiquitousKeyValueStore.postInternalChangeNotification(for: write.keyID, from: ubiquitousStore)
        let committed = try migrationSnapshot(for: write.keyID)
        guard PropertyListMigrationStorage.equal(write.object, committed?.object) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return committed
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        keyID.utf16.count > 128
    }

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        .literal(keyID)
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        guard let object = ubiquitousStore.object(forKey: keyID) else {
            return nil
        }

        let frozen = try PropertyListMigrationStorage.freeze(object, allowingLegacyURL: true)
        return MigrationSnapshot(identity: migrationIdentity, keyID: keyID, object: frozen)
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        let current = try migrationSnapshot(for: keyID)
        return PropertyListMigrationStorage.equal(snapshot.object, current?.object)
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == key.id else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        return try decodeStorageValue(for: key, object: snapshot.object, format: .ubiquitousKeyValueStore)
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        let object = try encodeStorageValue(value, for: key, format: .ubiquitousKeyValueStore)
        if let object {
            let frozen = try PropertyListMigrationStorage.freezeExactly(object)
            if try PropertyListMigrationStorage.byteCount(frozen) > 1_048_576 {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: frozen)
        }

        return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: nil)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        guard try migrationSnapshotIsCurrent(snapshot, for: keyID) else {
            throw PersistentKeyMigrationError.sourceChanged
        }

        ubiquitousStore.removeObject(forKey: keyID)
        NSUbiquitousKeyValueStore.postInternalChangeNotification(for: keyID, from: ubiquitousStore)
        guard try migrationSnapshot(for: keyID) == nil else {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }
    }
}

// MARK: - PersistentKeyValueMigrationRewriteBackend Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend: PersistentKeyValueMigrationRewriteBackend {
    // MARK: Internal Instance Interface

    /// A prepared write holds a frozen property list, so decoding it cannot change the write.
    func migrationValue<Key>(
        for key: Key,
        writtenBy write: MigrationWrite
    ) throws -> Key.Value? where Key: PersistentKeyProtocol {
        guard write.identity == migrationIdentity, write.keyID == key.id else {
            throw PersistentKeyMigrationError.internalInconsistency
        }

        return try write.object.map {
            try decodeStorageValue(for: key, object: $0, format: .ubiquitousKeyValueStore)
        }
    }

    func migrationWrite(_ write: MigrationWrite, matches other: MigrationWrite) -> Bool {
        PropertyListMigrationStorage.equal(write.object, other.object)
    }
}

// MARK: - MigrationSnapshot Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend {
    struct MigrationSnapshot {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any
    }
}

// MARK: - MigrationWrite Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend {
    struct MigrationWrite {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any?
    }
}
