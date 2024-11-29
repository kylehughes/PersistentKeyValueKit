//
//  FloatUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class FloatUserDefaultsTests: AbstractUserDefaultsTypeTests<Float> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Float] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }
}
