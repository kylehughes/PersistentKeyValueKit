//
//  LosslessStringConvertibleUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class LosslessStringConvertibleUserDefaultsTests:
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
