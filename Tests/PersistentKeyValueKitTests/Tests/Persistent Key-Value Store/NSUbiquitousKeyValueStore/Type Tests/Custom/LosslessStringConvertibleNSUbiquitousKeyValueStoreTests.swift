//
//  LosslessStringConvertibleNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class LosslessStringConvertibleNSUbiquitousKeyValueStoreTests:
    AbstractUserDefaultsTypeTests<CustomPersistibleType.LosslessStringConvertible>
{
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.LosslessStringConvertible] {
        [
            "C",
            "😂",
        ]
    }
}
