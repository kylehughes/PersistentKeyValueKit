//
//  KeyValueStorableAsCodable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueStorableAsCodable: Codable, KeyValueStorable
where
    Storage == String
{
    // NO-OP
}

// MARK: - KeyValueStorable Extension

extension KeyValueStorableAsCodable {
    // MARK: Interfacing with User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }

    #endif
}
