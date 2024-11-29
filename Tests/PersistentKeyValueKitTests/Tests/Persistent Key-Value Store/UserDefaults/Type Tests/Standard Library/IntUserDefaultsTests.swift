//
//  IntUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class IntUserDefaultsTests: AbstractUserDefaultsTypeTests<Int> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Int] {
        [
            .max,
            .min,
            .zero,
        ]
    }
}
