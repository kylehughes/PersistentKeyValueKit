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
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        switch self {
        case .none:
            userDefaults.removeObject(forKey: userDefaultsKey)
        case let .some(wrapped):
            wrapped.store(as: userDefaultsKey, in: userDefaults)
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
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        switch self {
        case .none:
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        case let .some(wrapped):
            wrapped.store(as: ubiquitousStoreKey, in: ubiquitousStore)
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
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard 
            let wrappedSerialization = serialization(),
            let unwrappedSerialization = wrappedSerialization
        else {
            return nil
        }
        
        return Wrapped.deserialize(from: unwrappedSerialization)
    }
    
    @inlinable
    public func serialize() -> Serialization {
        switch self {
        case .none:
            return nil
        case let .some(wrapped):
            return wrapped.serialize()
        }
    }
}

// MARK: - KeyValueStorable Extension

extension Optional: KeyValueStorable where Wrapped: KeyValueStorable {}
