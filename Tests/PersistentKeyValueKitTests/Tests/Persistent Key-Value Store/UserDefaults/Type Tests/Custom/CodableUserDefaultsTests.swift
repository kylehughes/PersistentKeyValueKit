//
//  CodableUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class CodableUserDefaultsTests: AbstractUserDefaultsTypeTests<CustomPersistibleType.Codable> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.Codable] {
        [
            .large,
            .small,
        ]
    }
}
