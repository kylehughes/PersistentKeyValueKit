import Foundation

/// The migration backend for one UserDefaults persistent domain.
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
        migrationIdentity = PersistentKeyValueMigrationStoreIdentity(namespace: "UserDefaults", identifier: domainName)
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension UserDefaultsMigrationBackend: PersistentKeyValueMigrationBackend {
    // MARK: Internal Instance Interface

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        guard write.identity == migrationIdentity else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }

        if let snapshot, !(try migrationSnapshotIsCurrent(snapshot, for: write.keyID)) {
            throw PersistentKeyMigrationError.destinationChanged
        }

        if snapshot == nil, try migrationSnapshot(for: write.keyID) != nil {
            throw PersistentKeyMigrationError.destinationChanged
        }

        if let object = write.object {
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

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        guard let object = userDefaults.persistentDomain(forName: domainName)?[keyID] else {
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
            throw PersistentKeyMigrationError.invalidSnapshot
        }

        let current = try migrationSnapshot(for: keyID)
        return PropertyListMigrationStorage.equal(snapshot.object, current?.object)
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == key.id else {
            throw PersistentKeyMigrationError.invalidSnapshot
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
                object: try PropertyListMigrationStorage.freeze(object)
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
