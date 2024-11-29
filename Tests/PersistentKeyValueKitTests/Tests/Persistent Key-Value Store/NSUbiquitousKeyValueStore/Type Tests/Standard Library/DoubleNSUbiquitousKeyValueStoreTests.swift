//
//  DoubleNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

@available(watchOS 9.0, *)
final class DoubleNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<Double> {
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
