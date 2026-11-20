//
//  CodableNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class CodableNSUbiquitousKeyValueStoreTests:
    AbstractNSUbiquitousKeyValueStoreTypeTests<CustomPersistibleType.Codable>
{
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.Codable] {
        [
            .large,
            .small,
        ]
    }
}
