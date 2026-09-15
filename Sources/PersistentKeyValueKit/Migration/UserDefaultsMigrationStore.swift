import Foundation

/// A migration adapter for one UserDefaults persistent domain.
///
/// The wrapped Foundation object and domain name are immutable after initialization. Subclasses used for testing must
/// preserve UserDefaults' thread-safety guarantees.
public final class UserDefaultsMigrationStore: @unchecked Sendable {
    /// The UserDefaults instance used for ordinary typed access.
    public let userDefaults: UserDefaults
    /// The persistent domain read and written by migration operations.
    public let domainName: String
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity

    /// Creates an adapter for a named persistent domain.
    ///
    /// The adapter creates the matching UserDefaults instance internally so its domain identity cannot be paired with
    /// an unrelated instance.
    public convenience init(suiteName: String) throws {
        try self.init(suiteName: suiteName, makeUserDefaults: { UserDefaults(suiteName: $0) })
    }

    internal convenience init(suiteName: String, makeUserDefaults: (String) -> UserDefaults?) throws {
        guard !suiteName.isEmpty else { throw PersistentKeyMigrationError.invalidStoreIdentifier }
        guard let defaults = makeUserDefaults(suiteName) else {
            throw PersistentKeyMigrationError.storeUnavailable
        }
        self.init(userDefaults: defaults, domainName: suiteName)
    }

    /// Creates an adapter for the application's standard persistent domain.
    ///
    /// Throws when the main bundle has no application identifier.
    public static func standard() throws -> Self {
        try standard(applicationIdentifier: Bundle.main.bundleIdentifier)
    }

    internal static func standard(applicationIdentifier: String?) throws -> Self {
        guard let identifier = applicationIdentifier, !identifier.isEmpty else {
            throw PersistentKeyMigrationError.missingApplicationIdentifier
        }
        return Self(userDefaults: .standard, domainName: identifier)
    }

    internal init(userDefaults: UserDefaults, domainName: String) {
        self.userDefaults = userDefaults
        self.domainName = domainName
        migrationIdentity = PersistentKeyValueMigrationStoreIdentity(namespace: "UserDefaults", identifier: domainName)
    }

    struct MigrationSnapshot {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any
    }
    struct MigrationWrite {
        let identity: PersistentKeyValueMigrationStoreIdentity
        let keyID: String
        let object: Any?
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        guard let object = userDefaults.persistentDomain(forName: domainName)?[keyID] else { return nil }
        return MigrationSnapshot(
            identity: migrationIdentity, keyID: keyID, object: try PropertyListMigrationStorage.freeze(object))
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }
        let current = try migrationSnapshot(for: keyID)
        return PropertyListMigrationStorage.equal(snapshot.object, current?.object)
    }

    func migrationValue<Key>(for key: Key, in snapshot: MigrationSnapshot) throws -> Key.Value
    where Key: PersistentKeyProtocol {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == key.id else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }
        return try decodeStorageValue(for: key, object: snapshot.object, format: .userDefaults)
    }

    func prepareMigrationWrite<Key>(_ value: Key.Value, for key: Key) throws -> MigrationWrite
    where Key: PersistentKeyProtocol {
        let object = try encodeStorageValue(value, for: key, format: .userDefaults)
        if let object {
            return MigrationWrite(
                identity: migrationIdentity, keyID: key.id, object: try PropertyListMigrationStorage.freeze(object))
        }
        return MigrationWrite(identity: migrationIdentity, keyID: key.id, object: nil)
    }

    func commitMigrationWrite(_ write: MigrationWrite, replacing snapshot: MigrationSnapshot?) throws
        -> MigrationSnapshot?
    {
        guard write.identity == migrationIdentity else { throw PersistentKeyMigrationError.invalidSnapshot }
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

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        guard snapshot.identity == migrationIdentity, snapshot.keyID == keyID else {
            throw PersistentKeyMigrationError.invalidSnapshot
        }
        guard try migrationSnapshotIsCurrent(snapshot, for: keyID) else {
            throw PersistentKeyMigrationError.sourceChanged
        }
        userDefaults.removeObject(forKey: keyID)
        guard try migrationSnapshot(for: keyID) == nil else {
            throw PersistentKeyMigrationError.removalVerificationFailed
        }
    }
}

extension UserDefaultsMigrationStore: PersistentKeyValueMigrationStore, PersistentKeyValueMigrationBackend {
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint { PersistentKeyValueMigrationEndpoint(backend: self) }
}

extension UserDefaultsMigrationStore: PersistentKeyValueStore {
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        userDefaults.get(key)
    }
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        userDefaults.set(key, to: value)
    }
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        userDefaults.remove(key)
    }
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        userDefaults.deregister(observer, for: key, context: context)
    }
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        userDefaults.register(observer: target, for: key, with: context, and: selector)
    }
}
