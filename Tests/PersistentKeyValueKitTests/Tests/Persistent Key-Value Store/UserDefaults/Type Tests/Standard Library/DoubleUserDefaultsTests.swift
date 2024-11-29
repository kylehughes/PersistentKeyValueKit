//
//  DoubleUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

final class DoubleUserDefaultsTests: AbstractUserDefaultsTypeTests<Double> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Double] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }
}
