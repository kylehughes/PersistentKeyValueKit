//
//  DefaultPersistentKeyValueStoreViewModifierTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import SwiftUI
import XCTest

final class DefaultPersistentKeyValueStoreViewModifierTests: XCTestCase {}

// MARK: - Initialization Tests

extension DefaultPersistentKeyValueStoreViewModifierTests {
    // MARK: Tests
    
    @MainActor
    func test_init() {
        let store = InMemoryPersistentKeyValueStore()
        let modifier = DefaultPersistentKeyValueStoreViewModifier(store: store)
        
        XCTAssertTrue(modifier.store as? InMemoryPersistentKeyValueStore === store)
    }
}

// MARK: - View Extension Tests

extension DefaultPersistentKeyValueStoreViewModifierTests {
    // MARK: Tests
    
    @MainActor
    func test_viewExtension_appliesModifier() {
        let store = InMemoryPersistentKeyValueStore()
        
        let view = Text("Test")
            .defaultPersistentKeyValueStore(store)
        
        XCTAssert(type(of: view) == ModifiedContent<Text, DefaultPersistentKeyValueStoreViewModifier>.self)
    }
}
