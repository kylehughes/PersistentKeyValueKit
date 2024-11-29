//
//  RawRepresentableUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class RawRepresentableUserDefaultsTests:
    AbstractUserDefaultsTypeTests<CustomPersistibleType.RawRepresentable>
{
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [CustomPersistibleType.RawRepresentable] {
        [
            .caseOne,
            .caseTwo,
        ]
    }
}
