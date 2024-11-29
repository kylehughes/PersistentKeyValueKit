//
//  InMemoryPersistentKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/28/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class InMemoryPersistentKeyValueStoreTests: AbstractPersistentKeyValueStoreTests<InMemoryPersistentKeyValueStore> {
    private let storage = InMemoryPersistentKeyValueStore()
    
    // MARK: AbstractPersistentKeyValueStoreTests Implementation
    
    override var target: InMemoryPersistentKeyValueStore {
        storage
    }
}
