import Foundation

/// The migration backend for one UserDefaults persistent domain.
///
/// Snapshots read `userDefaults`' persistent domain, and writes and removals go through `userDefaults` so its observers
/// are notified.
///
/// The wrapped Foundation object and domain name are immutable after initialization. Subclasses used for testing must
/// preserve UserDefaults' thread-safety guarantees.
final class UserDefaultsMigrationBackend: @unchecked Sendable {
    /// The persistent domain read and written by migration operations.
    let domainName: String

    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity

    /// The UserDefaults instance used for ordinary typed access.
    let userDefaults: UserDefaults

    // MARK: Internal Initialization

    internal init(userDefaults: UserDefaults, domainName: String) {
        self.userDefaults = userDefaults
        self.domainName = domainName
        migrationIdentity = PersistentKeyValueMigrationStoreIdentity(
            namespace: "UserDefaults",
            identifier: UserDefaults.migrationDomainIdentifier(domainName)
        )
    }
}

// MARK: - Persistent Domain Extension

extension UserDefaultsMigrationBackend {
    // MARK: Internal Instance Interface

    /// Returns the persisted domain as Foundation's own dictionary, or `nil` if Foundation returns no domain.
    ///
    /// Swift's `persistentDomain(forName:)` bridges the result to `[String: Any]`, which merges keys that are
    /// canonically equivalent but that Foundation stores separately, such as composed and decomposed spellings of
    /// "café". Sending the Objective-C message keeps the `NSDictionary`, whose key lookup is literal. The domain comes
    /// from `userDefaults` itself, so it resolves the same storage, including app group containers.
    func persistentDomain() -> NSDictionary? {
        userDefaults
            .perform(#selector(UserDefaults.persistentDomain(forName:)), with: domainName)?
            .takeUnretainedValue() as? NSDictionary
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension UserDefaultsMigrationBackend: PersistentKeyValueMigrationBackend {
    // MARK: Internal Instance Interface

    var migrationHandle: ObjectIdentifier {
        ObjectIdentifier(userDefaults)
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
            // Foundation ignores a write that Core Foundation considers equal to the stored value, such as `1` over
            // `true`, so a type-only change must replace the stored value.
            if let snapshot,
                !PropertyListMigrationStorage.equal(snapshot.object, object),
                CFEqual(snapshot.object as AnyObject, object as AnyObject)
            {
                userDefaults.removeObject(forKey: write.keyID)
                // Observers notified of the removal can write the key, and the replacement must not overwrite that.
                guard try migrationSnapshot(for: write.keyID) == nil else {
                    throw PersistentKeyMigrationError.destinationChanged
                }
            }

            userDefaults.set(object, forKey: write.keyID)
        } else {
            userDefaults.removeObject(forKey: write.keyID)
        }

        let committed = try migrationSnapshot(for: write.keyID)
        guard PropertyListMigrationStorage.equal(write.object, committed?.object) else {
            throw PersistentKeyMigrationError.writeVerificationFailed
        }

        return committed
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        false
    }

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        .literal(keyID)
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        guard let object = persistentDomain()?.object(forKey: keyID as NSString) else {
            return nil
        }

        return MigrationSnapshot(
            identity: migrationIdentity,
            keyID: keyID,
            object: try PropertyListMigrationStorage.freeze(object)
        )
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

        return try decodeStorageValue(for: key, object: snapshot.object, format: .userDefaults)
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        let object = try encodeStorageValue(value, for: key, format: .userDefaults)
        if let object {
            return MigrationWrite(
                identity: migrationIdentity,
                keyID: key.id,
                object: try PropertyListMigrationStorage.freezeExactly(object)
            )
        }

        return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: nil)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        guard try migrationSnapshotIsCurrent(snapshot, for: keyID) else {
            throw PersistentKeyMigrationError.sourceChanged
        }

        userDefaults.removeObject(forKey: keyID)
        guard try migrationSnapshot(for: keyID) == nil else {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }
    }
}

// MARK: - PersistentKeyValueMigrationRewriteBackend Extension

extension UserDefaultsMigrationBackend: PersistentKeyValueMigrationRewriteBackend {
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
            try decodeStorageValue(for: key, object: $0, format: .userDefaults)
        }
    }

    func migrationWrite(_ write: MigrationWrite, matches other: MigrationWrite) -> Bool {
        PropertyListMigrationStorage.equal(write.object, other.object)
    }
}

// MARK: - MigrationSnapshot Extension

extension UserDefaultsMigrationBackend {
    struct MigrationSnapshot {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any
    }
}

// MARK: - MigrationWrite Extension

extension UserDefaultsMigrationBackend {
    struct MigrationWrite {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any?
    }
}
