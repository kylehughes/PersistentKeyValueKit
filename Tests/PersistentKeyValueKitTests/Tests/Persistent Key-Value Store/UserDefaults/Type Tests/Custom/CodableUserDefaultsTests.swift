//
//  CodableUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
final class CodableUserDefaultsTests: AbstractUserDefaultsTypeTests<CustomPersistibleType.Codable> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.Codable] {
        [
            .large,
            .small,
        ]
    }
}
