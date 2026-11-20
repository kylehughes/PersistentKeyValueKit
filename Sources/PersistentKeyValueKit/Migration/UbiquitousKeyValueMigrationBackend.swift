//
//  UbiquitousKeyValueMigrationBackend.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation

/// The migration backend for an iCloud key-value store.
///
/// Snapshots and prepared writes hold exact immutable copies, so migration decodes the object that an ordinary read
/// returns and commits the object that an ordinary write stores.
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
    init(_ store: NSUbiquitousKeyValueStore) {
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

// MARK: - FoundationMigrationBackend Extension

@available(watchOS 9.0, *)
extension UbiquitousKeyValueMigrationBackend: FoundationMigrationBackend {
    // MARK: Internal Instance Interface

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
        guard PropertyListStorage.equal(write.object, committed?.object) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return committed
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        keyID.utf16.count > 128
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        guard let object = ubiquitousStore.object(forKey: keyID) else {
            return nil
        }

        // A top-level URL is a legacy value that the URL representation decodes.
        let copy = object is URL ? object : try PropertyListStorage.exactCopy(object)
        return MigrationSnapshot(identity: migrationIdentity, keyID: keyID, object: copy)
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        guard snapshot.identity == migrationIdentity, LiteralKeyID.match(snapshot.keyID, key.id) else {
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
            let copy = try PropertyListStorage.storableCopy(of: object)
            if try PropertyListStorage.byteCount(copy) > 1_048_576 {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: copy)
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
