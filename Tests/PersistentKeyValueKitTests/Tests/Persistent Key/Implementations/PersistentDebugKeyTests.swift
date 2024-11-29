//
//  PersistentDebugKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

final class PersistentDebugKeyTests: AbstractPersistentKeyTests<PersistentDebugKey<String>> {
    // MARK: AbstractPersistenKeyTests Implementation
    
    override var defaultValue: String {
        "defaultValue"
    }
    
    override var id: String {
        "key"
    }
    
    override var storedValue: String {
        "storedValue"
    }
    
    override var target: PersistentDebugKey<String> {
        PersistentDebugKey(id, defaultValue: defaultValue)
    }
    
    // MARK: Initialization Tests

    @MainActor
    func test_init_otherRepresentation() throws {
        try skipIfNotiOS16OrLaterOrEquivalent()
        
        let representation = ReferenceProxyPersistentKeyValueRepresentation<String, String>(
            serializing: \.self,
            deserializing: \.self
        )
        
        let key = PersistentDebugKey(id, defaultValue: defaultValue, representation: representation)

        XCTAssertEqual(key.id, id)
        XCTAssertEqual(key.defaultValue, defaultValue)
        XCTAssert(
            key.representation as? ReferenceProxyPersistentKeyValueRepresentation<String, String>
            === representation
        )
    }
    
    @MainActor
    func test_init_otherRepresentation_optional() throws {
        try skipIfNotiOS16OrLaterOrEquivalent()
        
        let representation = ReferenceProxyPersistentKeyValueRepresentation<String, String>(
            serializing: \.self,
            deserializing: \.self
        )
        
        let key = PersistentDebugKey<String?>(id, defaultValue: nil, representation: representation)

        XCTAssertEqual(key.id, id)
        XCTAssertEqual(key.defaultValue, nil)
        
        let baseRepresentation = try XCTUnwrap(
            key.representation as? OptionalPersistentKeyValueRepresentation<
                ReferenceProxyPersistentKeyValueRepresentation<String, String>
            >
        )
        
        XCTAssert(baseRepresentation.base === representation)
    }
    
    // MARK: Equatable Tests
    
    @MainActor
    func test_persistentKey_equatable() {
        let other = target
        
        XCTAssertEqual(target, other)
    }
    
    // MARK: Hashable Tests
    
    @MainActor
    func test_persistentKey_hashable() {
        let other = target
        
        XCTAssertEqual(target.hashValue, other.hashValue)
    }
}
