//
//  BoolNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

import PersistentKeyValueKit

final class BoolNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<Bool> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Bool] {
        [
            true,
            false
        ]
    }
}
