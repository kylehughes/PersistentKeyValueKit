//
//  LosslessStringConvertiblePersistentKeyValueRepresentationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/15/24.
//

import PersistentKeyValueKit
import XCTest

final class LosslessStringConvertiblePersistentKeyValueRepresentationTests: XCTestCase {}

// MARK: - UserDefaults Tests

extension LosslessStringConvertiblePersistentKeyValueRepresentationTests {
    // MARK: Tests
    
    func test_from() {
        let value = "1337"
        let representation = LosslessStringConvertiblePersistentKeyValueRepresentation<Int>()
        
        XCTAssertEqual(1337, representation.from(value))
    }
    
    func test_to() {
        let value = 1337
        let representation = LosslessStringConvertiblePersistentKeyValueRepresentation<Int>()
        
        XCTAssertEqual("1337", representation.to(value))
    }
}
