//
//  PersistentKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

final class PersistentKeyTests: AbstractPersistentKeyTests<PersistentKey<String>> {
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
    
    override var target: PersistentKey<String> {
        PersistentKey(id, defaultValue: defaultValue)
    }
    
    // MARK: Initialization Tests

    @MainActor
    func test_init_otherRepresentation() {
        let representation = ReferenceProxyPersistentKeyValueRepresentation<String, String>(
            serializing: \.self,
            deserializing: \.self
        )
        
        let key = PersistentKey(id, defaultValue: defaultValue, representation: representation)

        XCTAssertEqual(key.id, id)
        XCTAssertEqual(key.defaultValue, defaultValue)
        XCTAssert(
            key.representation as? ReferenceProxyPersistentKeyValueRepresentation<String, String>
            === representation
        )
    }
    
    @MainActor
    func test_init_otherRepresentation_optional() throws {
        let representation = ReferenceProxyPersistentKeyValueRepresentation<String, String>(
            serializing: \.self,
            deserializing: \.self
        )
        
        let key = PersistentKey<String?>(id, defaultValue: nil, representation: representation)

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

    func test_persistentKey_equatable_comparesIdentifiersLiterally() {
        let composed = PersistentKey("caf\u{E9}", defaultValue: 0)
        let decomposed = PersistentKey("cafe\u{301}", defaultValue: 0)

        XCTAssertEqual(composed.id, decomposed.id)
        XCTAssertNotEqual(composed, decomposed)
        XCTAssertEqual(composed, PersistentKey("caf\u{E9}", defaultValue: 0))
        XCTAssertNotEqual(composed, PersistentKey("caf\u{E9}", defaultValue: 1))
    }
    
    // MARK: Hashable Tests
    
    @MainActor
    func test_persistentKey_hashable() {
        let other = target
        
        XCTAssertEqual(target.hashValue, other.hashValue)
    }

    func test_persistentKey_hashable_keepsLiterallyDifferentIdentifiersSeparate() {
        let composed = PersistentKey("caf\u{E9}", defaultValue: 0)
        let decomposed = PersistentKey("cafe\u{301}", defaultValue: 0)

        XCTAssertEqual(Set([composed, decomposed, PersistentKey("caf\u{E9}", defaultValue: 0)]).count, 2)
        XCTAssertEqual(composed.hashValue, PersistentKey("caf\u{E9}", defaultValue: 0).hashValue)
    }
}
