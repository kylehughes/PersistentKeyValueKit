//
//  Optional+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - Storable Extension

extension Optional: Storable where Wrapped: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Wrapped.StorableValue?
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let wrappedStorableValue = storage(), let unwrappedStorableValue = wrappedStorableValue else {
            return nil
        }
        
        return Wrapped.decode(from: unwrappedStorableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        switch self {
        case .none:
            return nil
        case let .some(wrapped):
            return wrapped.encodeForStorage()
        }
    }

    // MARK: Interfacing with User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        Wrapped.extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        switch self {
        case .none:
            userDefaults.removeObject(forKey: userDefaultsKey)
        case let .some(wrapped):
            wrapped.store(wrapped.encodeForStorage(), as: userDefaultsKey, in: userDefaults)
        }
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        Wrapped.extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        switch self {
        case .none:
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        case let .some(wrapped):
            wrapped.store(wrapped.encodeForStorage(), as: ubiquitousStoreKey, in: ubiquitousStore)
        }
    }

    #endif
}
