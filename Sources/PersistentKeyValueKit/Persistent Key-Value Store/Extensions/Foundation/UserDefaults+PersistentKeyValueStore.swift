//
//  UserDefaults+PersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation
import ObjectiveC

// MARK: - PersistentKeyValueStore Extension

extension UserDefaults: PersistentKeyValueStore {
    /// The migration capability for this `UserDefaults` instance.
    ///
    /// Throws ``PersistentKeyMigrationError/missingApplicationIdentifier`` for `UserDefaults.standard` when
    /// `Bundle.main.bundleIdentifier` is missing or empty, or ``PersistentKeyMigrationError/missingMigrationDomain``
    /// for a non-standard instance that was not created with `UserDefaults.migratable(suiteName:)`.
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            let domainName = try UserDefaults.migrationDomainName(
                for: self,
                applicationIdentifier: Bundle.main.bundleIdentifier
            )

            return PersistentKeyValueMigrationEndpoint(
                backend: UserDefaultsMigrationBackend(userDefaults: self, domainName: domainName)
            )
        }
    }

    // MARK: Getting Values
    
    @inlinable
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        key.get(from: self)
    }
    
    // MARK: Setting Values
    
    @inlinable
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        key.set(to: value, in: self)
    }
    
    // MARK: Removing Values
    
    @inlinable
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        key.remove(from: self)
    }
    
    // MARK: Observing Keys
    
    @inlinable
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        removeObserver(observer, forKeyPath: key.id, context: context)
    }
    
    @inlinable
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        addObserver(target, forKeyPath: key.id, context: context)
    }
}

// MARK: - Bespoke Implementation

extension UserDefaults {
    // MARK: Register Default Values

    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
    @inlinable
    public func register(_ keys: any PersistentKeyProtocol...) {
       register(keys)
    }
    
    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
    public func register(_ keys: [any PersistentKeyProtocol]) {
        var defaults: [String: Any] = Dictionary(minimumCapacity: keys.count)
        
        for key in keys {
            key.registerDefault(in: &defaults)
        }
        
        register(defaults: defaults)
    }

    @inlinable
    internal func argumentDomainString(forKey key: String, visibleObject: Any?) -> String? {
        // `volatileDomain(forName:)` materializes the whole domain. First check the effective object so typed
        // stored values avoid that work on every read.
        guard visibleObject is String else {
            return nil
        }

        return volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
    }
}

// MARK: - Static Accessors

extension PersistentKeyValueStore where Self == UserDefaults {
    // MARK: Public Static Interface
    
    /// A convenient way to access `UserDefaults.standard`.
    ///
    /// If you construct your own `UserDefaults` for an app group, we encourage you to make your own static accessor
    /// for your convenience.
    @inlinable
    public static var local: Self {
        .standard
    }

    /// Creates a native `UserDefaults` instance for `suiteName` that can participate in migrations.
    ///
    /// The returned value is the native `UserDefaults` instance from `UserDefaults(suiteName:)` with `suiteName`
    /// attached as process-local metadata. The metadata is not written to preferences, does not retain the
    /// `UserDefaults` instance, and lasts only for the lifetime of that instance in the current process.
    ///
    /// - Parameter suiteName: The persistent domain identifier for the suite.
    /// - Returns: A `UserDefaults` instance configured for migration, or `nil` if `suiteName` is empty, matches a
    ///   reserved domain (`argumentDomain`, `registrationDomain`, `globalDomain`, `kCFPreferencesAnyApplication`, or
    ///   `kCFPreferencesCurrentApplication`), matches the main bundle identifier, or cannot be created by Foundation.
    public static func migratable(suiteName: String) -> Self? {
        Self.migratable(
            suiteName: suiteName,
            makeUserDefaults: {
                UserDefaults(suiteName: $0)
            }
        )
    }
}

private final class UserDefaultsMigrationDomainAssociationKey: Sendable {
}

final class UserDefaultsMigrationDomain: Sendable {
    let name: String

    init(name: String) {
        self.name = name
    }
}

extension UserDefaults {
    // MARK: Fileprivate Static Interface

    // A stable object address gives Objective-C associations an immutable process-local key without a mutable global.
    fileprivate static let migrationDomainAssociationToken = UserDefaultsMigrationDomainAssociationKey()

    // MARK: Internal Static Interface

    internal static func isValidMigrationDomain(
        _ name: String,
        applicationIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        // Core Foundation aliases can refer to the same store under a different migration identity.
        guard !name.isEmpty,
            name != argumentDomain,
            name != registrationDomain,
            name != globalDomain,
            name != kCFPreferencesAnyApplication as String,
            name != kCFPreferencesCurrentApplication as String
        else {
            return false
        }

        return name != applicationIdentifier
    }

    internal static func migratable(
        suiteName: String,
        makeUserDefaults: (String) -> UserDefaults?
    ) -> UserDefaults? {
        guard isValidMigrationDomain(suiteName) else {
            return nil
        }

        guard let defaults = makeUserDefaults(suiteName) else {
            return nil
        }

        objc_setAssociatedObject(
            defaults,
            migrationDomainAssociationAddress,
            // The metadata is retained by the native object and never retains a backend or the object itself.
            UserDefaultsMigrationDomain(name: suiteName),
            .OBJC_ASSOCIATION_RETAIN
        )

        return defaults
    }

    internal static func migrationDomainMetadata(for defaults: UserDefaults) -> UserDefaultsMigrationDomain? {
        objc_getAssociatedObject(defaults, migrationDomainAssociationAddress) as? UserDefaultsMigrationDomain
    }

    internal static func migrationDomainName(
        for defaults: UserDefaults,
        applicationIdentifier: String?
    ) throws -> String {
        if defaults === UserDefaults.standard {
            guard let applicationIdentifier, !applicationIdentifier.isEmpty else {
                throw PersistentKeyMigrationError.missingApplicationIdentifier
            }

            return applicationIdentifier
        }

        guard let metadata = migrationDomainMetadata(for: defaults) else {
            throw PersistentKeyMigrationError.missingMigrationDomain
        }

        return metadata.name
    }

    // MARK: Fileprivate Static Interface

    fileprivate static var migrationDomainAssociationAddress: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(migrationDomainAssociationToken).toOpaque())
    }
}
