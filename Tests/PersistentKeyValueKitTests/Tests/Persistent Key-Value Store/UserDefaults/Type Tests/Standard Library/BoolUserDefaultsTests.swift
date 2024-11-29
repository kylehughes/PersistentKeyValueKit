//
//  BoolUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class BoolUserDefaultsTests: AbstractUserDefaultsTypeTests<Bool> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Bool] {
        [
            true,
            false
        ]
    }
}
