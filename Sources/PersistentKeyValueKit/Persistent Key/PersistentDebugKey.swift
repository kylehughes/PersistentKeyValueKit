//
//  PersistentDebugKey.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/9/22.
//

import Foundation

/// A key for a value in a ``PersistentKeyValueStore`` that is only mutable in debug builds.
///
/// In production builds, the default value is always returned and setting the value has no effect.
///
/// e.g.
///
/// ```swift
/// extension PersistentKeyProtocol where Self == PersistentDebugKey<Bool> {
///     static var isAppStoreRatingEnabled: Self {
///         Self(id: "IsAppStoreRatingEnabled", defaultValue: true) 
///     }
/// }
/// …
/// userDefaults.get(.isAppStoreRatingEnabled)
/// ```
public struct PersistentDebugKey<Value>: Identifiable, PersistentKeyProtocol where Value: KeyValuePersistible {
    /// The default value for the key.
    ///
    /// In debug builds, this value is used when the key has not been set. In production builds, this value is always 
    /// used.
    public let defaultValue: Value

    /// The unique identifier for the key.
    ///
    /// This value must be unique across all keys in a given ``PersistentKeyValueStore``.
    public let id: String
    
    /// The representation of the key-value pair in the ``PersistentKeyValueStore``.
    public let representation: any PersistentKeyValueRepresentation<Value>
    
    // MARK: Public Initialization
    
    /// Creates a new key with the given identifier and default value.
    ///
    /// The key-value pair is represented by the default representation for ``Value``.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
    @inlinable
    public init(
        id: String,
        defaultValue: Value
    ) {
        self.id = id
        self.defaultValue = defaultValue
        
        representation = Value.persistentKeyValueRepresentation
    }
    
    /// Creates a new key with the given identifier and default value.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
    @inlinable
    public init(
        id: String,
        defaultValue: Value,
        representation: some PersistentKeyValueRepresentation<Value>
    ) {
        self.id = id
        self.defaultValue = defaultValue
        self.representation = representation
    }
}

// MARK: - PersistentKeyProtocol Extension

extension PersistentDebugKey {
    // MARK: Interfacing with User Defaults
    
    /// In debug builds, gets the value of the key from the given `UserDefaults`.
    ///
    /// In debug builds, the default value is returned if the key has not been set. In production builds, the default
    /// value is always returned.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to get the value from.
    /// - Returns: In debug builds, the value of the key in the given `UserDefaults`, or the default value if the key 
    ///   has not been set. In production builds, the default value.
    @inlinable
    public func get(from userDefaults: UserDefaults) -> Value {
        #if DEBUG
        representation.get(id, from: userDefaults) ?? defaultValue
        #else
        defaultValue
        #endif
    }

    /// In debug builds, removes the value of the key from the given `UserDefaults`.
    /// 
    /// In production builds, this method has no effect.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to remove the value from.
    @inlinable
    public func remove(from userDefaults: UserDefaults) {
        #if DEBUG
        userDefaults.removeObject(forKey: id)
        #else
        // NO-OP
        #endif
    }
    
    /// In debug builds, sets the value of the key to the given value in the given `UserDefaults`.
    ///
    /// In production builds, this method has no effect.
    ///
    /// - Parameter newValue: The new value for the key.
    @inlinable
    public func set(to newValue: Value, in userDefaults: UserDefaults) {
        #if DEBUG
        representation.set(id, to: newValue, in: userDefaults)
        #else
        // NO-OP
        #endif
    }
    
    #if !os(watchOS)

    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// In debug builds, gets the value of the key from the given `NSUbiquitousKeyValueStore`. The default value is 
    /// returned if the key has not been set. 
    ///
    /// In production builds, the default value is always returned.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from.
    /// - Returns: In debug builds, the value of the key in the given `NSUbiquitousKeyValueStore`, or the default value
    ///   if the key has not been set. In production builds, the default value.
    @inlinable
    public func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value {
        #if DEBUG
        representation.get(id, from: ubiquitousStore) ?? defaultValue
        #else
        defaultValue
        #endif
    }
    
    /// In debug builds, removes the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// In production builds, this method has no effect.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to remove the value from.
    @inlinable
    public func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        #if DEBUG
        ubiquitousStore.removeObject(forKey: id)
        #else
        // NO-OP
        #endif
    }

    /// In debug builds, sets the value of the key to the given value in the given `NSUbiquitousKeyValueStore`.
    ///
    /// In production builds, this method has no effect.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in.
    @inlinable
    public func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        #if DEBUG
        representation.set(id, to: newValue, in: ubiquitousStore)
        #else
        // NO-OP
        #endif
    }
    
    #endif
}

// MARK: - Conditional Equatable Extension

extension PersistentDebugKey: Equatable where Value: Equatable {
    // MARK: Public Static Interface
    
    @inlinable
    public static func == (lhs: PersistentDebugKey<Value>, rhs: PersistentDebugKey<Value>) -> Bool {
        lhs.defaultValue == rhs.defaultValue && lhs.id == rhs.id
    }
}

// MARK: - Conditional Hashable Extension

extension PersistentDebugKey: Hashable where Value: Hashable {
    // MARK: Public Instance Interface
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(defaultValue)
        hasher.combine(id)
    }
}
