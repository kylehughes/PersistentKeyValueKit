//
//  PersistentKeyProtocol.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/17/22.
//

import CryptoKit
import Foundation

/// A typed key for a value in a ``PersistentKeyValueStore``.
///
/// This protocol models keys backed by `UserDefaults`, `NSUbiquitousKeyValueStore`, or
/// ``InMemoryPersistentKeyValueStore``. Each store reads, writes, and removes a value by calling the key's
/// `get(from:)`, `set(to:in:)`, and `remove(from:)` requirements for that store, so a conforming type controls access
/// to every store it supports. The `UserDefaults` and `NSUbiquitousKeyValueStore` requirements have no default
/// implementations. The ``InMemoryPersistentKeyValueStore`` requirements default to storing the Swift value directly
/// through ``InMemoryPersistentKeyValueStore/object(forKey:)``, ``InMemoryPersistentKeyValueStore/set(_:forKey:)``,
/// and ``InMemoryPersistentKeyValueStore/removeObject(forKey:)``.
///
/// - Important: A key's value lives under its ``id`` in every store. Observation watches that identifier for changes,
///   and migration reads, writes, and removes the value there without calling these requirements. An implementation
///   can change how a value is read, written, or gated, such as by clamping values or ignoring writes, but must keep
///   the value under ``id``.
public protocol PersistentKeyProtocol<Value>: Identifiable, Sendable where ID == String {
    // MARK: Associated Types
    
    /// The type of the value for the key.
    associatedtype Value

    
    // MARK: Instance Interface

    /// The default value for the key.
    ///
    /// This value is used when the key has not been set.
    var defaultValue: Value { get }

    /// The unique identifier for the key.
    ///
    /// This is the string key used in the underlying stores, and the store-specific requirements must keep the value
    /// under it.
    ///
    /// `UserDefaults` and `NSUbiquitousKeyValueStore` compare identifiers literally, so canonically equivalent
    /// spellings, such as composed and decomposed "café", are different keys. `ID` is `String`, which treats those
    /// spellings as equal, so `Identifiable` identity merges them: SwiftUI's `ForEach(keys)` shows one row for both.
    /// To give each stored key its own row, identify it by its identifier's UTF-8 code units:
    /// `ForEach(keys, id: \.id.utf8CString)`. UTF-8 cannot represent an unpaired UTF-16 surrogate, such as one left by
    /// truncating an emoji with `NSString.substring(to:)`, so identifiers that differ only in such surrogates still
    /// share a row. Key equality is not a substitute: synthesized equality compares identifiers as strings, and
    /// ``PersistentKey`` and ``PersistentDebugKey`` equality also compares default values, so with `\.self`, changing
    /// only a key's default value recreates its row.
    ///
    /// - Important: This value must be unique across all keys in a given ``PersistentKeyValueStore``. If it is backed
    ///   by a Foundation string, reading its characters must not access a store; Foundation may hold its own locks
    ///   while it reads a key.
    var id: ID { get }

    /// Whether this key participates in migration operations.
    ///
    /// When `false`, migration skips the key without accessing the source or destination store and reports
    /// ``PersistentKeyMigrationReport/Status/keyDisabled``. The default implementation returns `true`.
    var isMigrationEnabled: Bool { get }
    
    /// The representation of the key-value pair in the ``PersistentKeyValueStore``.
    var representation: any PersistentKeyValueRepresentation<Value> { get }

    // MARK: Interfacing with User Defaults
    
    /// Gets the value of the key from the given `UserDefaults`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to get the value from.
    /// - Returns: The value of the key in the given `UserDefaults`, or the default value if the key has not been set.
    func get(from userDefaults: UserDefaults) -> Value

    /// Removes the value of the key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to remove the value from.
    func remove(from userDefaults: UserDefaults)

    /// Sets the value of the key to the given value in the given `UserDefaults`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in.
    func set(to newValue: Value, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Gets the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from.
    /// - Returns: The value of the key in the given `NSUbiquitousKeyValueStore`, or the default value if the key has 
    ///   not been set.
    @available(watchOS 9.0, *)
    func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value

    /// Removes the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to remove the value from.
    @available(watchOS 9.0, *)
    func remove(from ubiquitousStore: NSUbiquitousKeyValueStore)

    /// Sets the value of the key to the given value in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in.
    @available(watchOS 9.0, *)
    func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)

    // MARK: Interfacing with In-Memory Store

    /// Gets the value of the key from the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to get the value from.
    /// - Returns: The value of the key in the given ``InMemoryPersistentKeyValueStore``, or the default value if the
    ///   key has not been set.
    func get(from inMemoryStore: InMemoryPersistentKeyValueStore) -> Value

    /// Removes the value of the key from the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to remove the value from.
    func remove(from inMemoryStore: InMemoryPersistentKeyValueStore)

    /// Sets the value of the key to the given value in the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to set the value in.
    func set(to newValue: Value, in inMemoryStore: InMemoryPersistentKeyValueStore)
}

// MARK: - Bespoke Implementation

extension PersistentKeyProtocol {
    // MARK: Public Instance Interface

    public var isMigrationEnabled: Bool {
        true
    }

    /// Registers the default value for the key in the given registration dictionary for `UserDefaults`.
    ///
    /// This is intended for use by `UserDefaults.register(_:)` to register the default values for the keys. The
    /// default value is encoded with ``PersistentKeyValueStorageFormat/userDefaults``, the same form that a write to
    /// `UserDefaults` stores, so reading an unset key returns the registered default through the ordinary read path.
    /// Leaves `propertyListDictionary` unchanged when encoding the default value fails, and removes the entry when it
    /// encodes to `nil`.
    ///
    /// A Swift dictionary treats identifiers that are canonically equivalent but spelled differently, such as composed
    /// and decomposed "café", as one key. `UserDefaults.register(_:)` keeps such identifiers separate, as
    /// `UserDefaults` does.
    ///
    /// - Parameter propertyListDictionary: The dictionary to register the default value in.
    public func registerDefault(in propertyListDictionary: inout [String: Any]) {
        guard let object = registeredDefaultObject() else {
            return
        }

        if let object {
            propertyListDictionary[id] = object
        } else {
            propertyListDictionary.removeValue(forKey: id)
        }
    }

    // MARK: Interfacing with In-Memory Store

    /// Gets the value of the key from the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// The default implementation returns the stored value when it is a `Value`, including an explicitly stored `nil`
    /// for an optional key, and returns the default value when the key has not been set or the stored value has
    /// another type.
    ///
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to get the value from.
    /// - Returns: The value of the key in the given ``InMemoryPersistentKeyValueStore``, or the default value if the
    ///   key has not been set.
    @inlinable
    public func get(from inMemoryStore: InMemoryPersistentKeyValueStore) -> Value {
        guard let object = inMemoryStore.object(forKey: id) else {
            return defaultValue
        }

        return object as? Value ?? defaultValue
    }

    /// Removes the value of the key from the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// The default implementation calls ``InMemoryPersistentKeyValueStore/removeObject(forKey:)``.
    ///
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to remove the value from.
    @inlinable
    public func remove(from inMemoryStore: InMemoryPersistentKeyValueStore) {
        inMemoryStore.removeObject(forKey: id)
    }

    /// Sets the value of the key to the given value in the given ``InMemoryPersistentKeyValueStore``.
    ///
    /// The default implementation calls ``InMemoryPersistentKeyValueStore/set(_:forKey:)``, so setting an optional
    /// key to `nil` records an explicit entry.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter inMemoryStore: The ``InMemoryPersistentKeyValueStore`` to set the value in.
    @inlinable
    public func set(to newValue: Value, in inMemoryStore: InMemoryPersistentKeyValueStore) {
        inMemoryStore.set(newValue, forKey: id)
    }

    // MARK: Internal Instance Interface

    /// Registers the default value for the key in the given Foundation registration dictionary, which keys entries by
    /// their literal identifiers.
    ///
    /// Behaves like ``registerDefault(in:)`` otherwise.
    internal func registerDefault(inLiteralDictionary propertyListDictionary: NSMutableDictionary) {
        guard let object = registeredDefaultObject() else {
            return
        }

        if let object {
            propertyListDictionary[id as NSString] = object
        } else {
            propertyListDictionary.removeObject(forKey: id as NSString)
        }
    }

    // MARK: Private Instance Interface

    /// Returns the object to register for the default value: `nil` when encoding fails, or `.some(nil)` when the
    /// default value encodes to `nil` and its entry should be removed.
    private func registeredDefaultObject() -> Any?? {
        do {
            return storableEncoding(try representation.encode(defaultValue, format: .userDefaults))
        } catch {
            return nil
        }
    }
}

extension PersistentKeyProtocol where Self == PersistentKey<Bool> {
    /// Returns the persistent boolean key used to record completion for a migration identifier with
    /// ``PersistentKeyMigrationTracking/once(id:)`` or ``PersistentKeyMigrationTracking/once(id:recordedIn:)``.
    ///
    /// Remove this key from the recording store (or set it to `false`) to allow a completed migration with the same
    /// `id` to run again.
    ///
    /// Identifiers that are equal as Swift strings, including precomposed and decomposed spellings of the same accented
    /// character, return the same key. Identifiers that differ in any other way, including case, return different keys.
    ///
    /// The key's identifier has the same length for every `id`, so identifiers of any length can be recorded in any
    /// store, including `NSUbiquitousKeyValueStore`. It contains no `.`, so `UserDefaults` key-value observation can
    /// observe it.
    ///
    /// - Parameter id: The migration identifier passed to ``PersistentKeyMigrationTracking/once(id:)`` or
    ///   ``PersistentKeyMigrationTracking/once(id:recordedIn:)``.
    /// - Returns: A boolean key whose default value is `false`.
    public static func isMigrationCompleted(id: String) -> Self {
        // A digest keeps the marker within `NSUbiquitousKeyValueStore`'s 128-unit key limit for any `id`. Hashing the
        // NFC form gives canonically equivalent identifiers, which Swift considers equal, the same marker.
        let digest = Data(SHA256.hash(data: Data(id.precomposedStringWithCanonicalMapping.utf8)))
        return Self(
            PersistentKeyMigrationTracking.completionMarkerPrefix
            + digest.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: ""),
            defaultValue: false
        )
    }
}
