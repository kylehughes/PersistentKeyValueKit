//
//  IntNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

import PersistentKeyValueKit

@available(watchOS 9.0, *)
final class IntNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<Int> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Int] {
        [
            .max,
            .min,
            .zero,
        ]
    }
}
