//
//  ArrayNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

/// - Important: While each type is exhaustively tested in arrays in the abstract test class, it is still useful to
///   test nested arrays. Here, we do not go for complete exhaustion – every type as nested arrays – because we could
///   then justify an infinite number of array-of-array-of… tests.
@available(watchOS 9.0, *)
final class ArrayNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<Array<Float>> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [[Float]] {
        [
            [
                .greatestFiniteMagnitude,
                .leastNonzeroMagnitude,
                .infinity,
                .zero,
            ]
        ]
    }
}
