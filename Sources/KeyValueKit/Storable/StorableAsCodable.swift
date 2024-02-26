//
//  StorableAsCodable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol StorableAsCodable: Codable, Storable, StorableAsProxy
where
    StorableValue == String
{}

// MARK: - Storable Implementation

extension StorableAsCodable {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard
            let jsonString = storage(),
            let json = jsonString.data(using: .utf8),
            let value = try? JSONDecoder().decode(Self.self, from: json)
        else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing With Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }

    #endif
}
