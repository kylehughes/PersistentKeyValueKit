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
    
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        let keyID = key.id

        guard Self.supportsKeyValueObservation(of: keyID) else {
            StoreKeyObservationRegistry.registry(for: self).remove(observer, keyID: keyID, context: context)

            return
        }

        removeObserver(observer, forKeyPath: keyID, context: context)
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        let keyID = key.id

        guard Self.supportsKeyValueObservation(of: keyID) else {
            StoreKeyObservationRegistry.registry(for: self).insert(
                UserDefaultsKeyChangeObservation(
                    observer: target,
                    keyID: keyID,
                    context: context,
                    monitor: .monitor(for: self)
                )
            )

            return
        }

        addObserver(target, forKeyPath: keyID, context: context)
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
    /// Each key's default value is encoded with ``PersistentKeyValueStorageFormat/userDefaults``. Keys whose default
    /// values fail to encode (such as a file `URL` whose stored path cannot reproduce its `absoluteString`, for which
    /// typed ``get(_:)`` still returns `defaultValue` while `url(forKey:)` returns `nil` when no other value is
    /// visible) are skipped, and keys whose default values encode to `nil` are removed from the registration
    /// dictionary.
    ///
    /// Identifiers are compared literally, as `UserDefaults` compares them, so identifiers that are canonically
    /// equivalent but spelled differently register separately. When two keys have the same identifier, the later one
    /// wins. A default that encodes to `nil` is removed only from the dictionary being filled, while a default already
    /// submitted in a separate `UserDefaults.register(_:)` call in the same process remains registered.
    ///
    /// The registration domain is volatile, so register on every launch in each app or extension process, before raw
    /// `UserDefaults` readers need the fallbacks. Every `UserDefaults` instance in the process shares it, so
    /// registering an identifier in another suite can replace its fallback everywhere in that process. Typed reads
    /// decode a visible registered object, so the result can differ from the key's `defaultValue` when encoding loses
    /// information, such as an array encoding that omits `nil` elements, and registration can change the value that an
    /// unset key returns.
    ///
    /// A `URL` default registers as its checked `.userDefaults` encoding: a representable file URL as a path and any
    /// other URL as archive data. Earlier versions registered `absoluteString`, so raw `string(forKey:)` on a registered
    /// non-file URL default now returns `nil`; use `url(forKey:)` for raw access.
    ///
    /// - Parameter keys: The keys to register.
    public func register(_ keys: [any PersistentKeyProtocol]) {
        // `register(defaults:)` takes a Swift dictionary, which merges canonically equivalent identifiers. Sending the
        // Objective-C message with Foundation's own dictionary keeps them separate.
        let defaults = NSMutableDictionary(capacity: keys.count)

        for key in keys {
            key.registerDefault(inLiteralDictionary: defaults)
        }

        _ = perform(#selector(UserDefaults.register(defaults:)), with: defaults)
    }

    // MARK: Internal Static Interface

    /// Returns whether key-value observation can observe the defaults key with the given identifier.
    ///
    /// Key-value observation parses the identifier as a key path, so it cannot observe every literal defaults key. It
    /// raises an exception for the empty identifier and for one containing a NUL character, and it treats a period as
    /// a component separator, raising an exception or never reporting changes. It treats a leading `@` as a collection
    /// operator and never reports changes. For `valueForKey:`, with its first letter in either case, it calls
    /// `NSObject`'s `keyPathsForValuesAffectingValueForKey:` without an argument and crashes.
    internal static func supportsKeyValueObservation(of keyID: String) -> Bool {
        // Key-value observation reads code units, so a period or `@` that combines with the following scalar into one
        // `Character` still separates components or names an operator.
        let utf8 = keyID.utf8

        guard let first = utf8.first, first != UInt8(ascii: "@") else {
            return false
        }

        return !utf8.contains { $0 == UInt8(ascii: ".") || $0 == 0 }
            && !utf8.elementsEqual("valueForKey:".utf8)
            && !utf8.elementsEqual("ValueForKey:".utf8)
    }

    // MARK: Internal Instance Interface

    /// Returns the launch argument for `key` when it is the visible value, or `nil` when the visible value comes from
    /// another domain.
    @inlinable
    internal func argumentDomainString(forKey key: String, visibleObject: Any?) -> String? {
        // `volatileDomain(forName:)` materializes the whole domain. First check the effective object so typed
        // stored values avoid that work on every read.
        guard let visibleString = visibleObject as? String else {
            return nil
        }

        // A managed (forced) preference outranks the argument domain, so the visible string may be the managed
        // value even when a launch argument exists. Parse only a visible value that is the launch argument.
        // Swift's `volatileDomain(forName:)` bridges the domain to a Swift dictionary, whose lookup also matches a
        // canonically equivalent but differently spelled argument. Foundation's own dictionary matches literally.
        guard
            let argumentDomain = perform(
                #selector(UserDefaults.volatileDomain(forName:)),
                with: UserDefaults.argumentDomain
            )?.takeUnretainedValue() as? NSDictionary,
            let argument = argumentDomain.object(forKey: key) as? String,
            (argument as NSString).isEqual(to: visibleString),
            !objectIsForced(forKey: key)
        else {
            return nil
        }

        return argument
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
    /// Migration treats suite names that differ only by case or Unicode normalization as the same store, because they
    /// can share one preferences file. Path-shaped names, names ending in `.plist`, and names containing NUL are
    /// rejected, because Foundation can resolve them to the preferences of another suite name.
    ///
    /// - Parameter suiteName: The persistent domain identifier for the suite, such as an app group identifier.
    /// - Returns: A `UserDefaults` instance configured for migration, or `nil` if `suiteName` is empty, contains `/` or
    ///   NUL, begins with `~`, ends with `.plist` ignoring case, matches a reserved domain (`argumentDomain`,
    ///   `registrationDomain`, `globalDomain`, `kCFPreferencesAnyApplication`, or `kCFPreferencesCurrentApplication`)
    ///   or the main bundle identifier ignoring case and Unicode normalization, or cannot be created by Foundation.
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
        let reservedNames = [
            argumentDomain,
            registrationDomain,
            globalDomain,
            kCFPreferencesAnyApplication as String,
            kCFPreferencesCurrentApplication as String,
            applicationIdentifier,
        ]
        let foldedName = migrationDomainIdentifier(name)

        // Core Foundation resolves a name containing `/` as a preferences file path, and it removes a `.plist` suffix
        // in any case, so these names can open another name's preferences file under a different identity. A leading
        // `~` is rejected as path-shaped too. Core Foundation reads these delimiters as code units, while Swift's
        // `Character` comparison would miss one followed by a combining mark. Core Foundation also ends a name at its
        // first NUL, so names that differ only after one open the same domain under different identities.
        guard
            !name.isEmpty,
            !name.utf8.contains(0),
            !name.utf8.contains(UInt8(ascii: "/")),
            name.utf8.first != UInt8(ascii: "~"),
            !foldedName.utf8.reversed().starts(with: ".plist".utf8.reversed())
        else {
            return false
        }

        return !reservedNames.contains { $0.map(migrationDomainIdentifier) == foldedName }
    }

    /// Returns the identifier that identifies a persistent domain across names that differ only by case or Unicode
    /// normalization.
    ///
    /// Preference files on case-insensitive or normalization-insensitive file systems are shared by such names, while
    /// the preferences daemon caches each name separately. Swift string comparison already treats canonically
    /// equivalent identifiers as equal, so only case needs folding.
    internal static func migrationDomainIdentifier(_ name: String) -> String {
        name.folding(options: .caseInsensitive, locale: nil)
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
