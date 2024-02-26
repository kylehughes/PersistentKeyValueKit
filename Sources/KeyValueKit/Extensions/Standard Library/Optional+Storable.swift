//
//  Optional+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension Optional: KeyValuePersistable where Wrapped: KeyValuePersistable {
    // MARK: Public Typealiases
    
    public typealias Persistence = Wrapped.Persistence?
    
    // MARK: Interfacing with User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        Wrapped.extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(_ value: Persistence, as userDefaultsKey: String, in userDefaults: UserDefaults) {
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
    ) -> Persistence? {
        Wrapped.extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        _ value: Persistence,
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

// MARK: - KeyValueSerializable Extension

extension Optional: KeyValueSerializable where Wrapped: KeyValueSerializable {
    // MARK: Public Typealiases
    
    public typealias Serialization = Wrapped.Serialization?
    
    // MARK: Serialization & Deserialization
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> Serialization?) -> Self? {
        guard 
            let wrappedKeyValueStorableValue = storage(),
            let unwrappedKeyValueStorableValue = wrappedKeyValueStorableValue
        else {
            return nil
        }
        
        return Wrapped.decode(from: unwrappedKeyValueStorableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> Serialization {
        switch self {
        case .none:
            return nil
        case let .some(wrapped):
            return wrapped.encodeForStorage()
        }
    }
}

// MARK: - KeyValueStorable Extension

extension Optional: KeyValueStorable where Wrapped: KeyValueStorable {}
