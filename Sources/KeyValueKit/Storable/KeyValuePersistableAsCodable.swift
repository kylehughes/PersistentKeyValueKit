//
//  KeyValuePersistableAsCodable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValuePersistableAsCodable: Codable, KeyValuePersistable
where
    Persistence == String
{}

// MARK: - KeyValuePersistable Extension

extension KeyValuePersistableAsCodable {
    // MARK: Interfacing with User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Persistence? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }

    #endif
}
