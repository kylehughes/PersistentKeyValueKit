//
//  PersistentKeyProtocolTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

final class PersistentKeyProtocolTests: XCTestCase {
    private let userDefaults = UserDefaults()
    
    // MARK: XCTestCase Implementation
    
    override func tearDown() {
        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
    }
}

// MARK: - General Tests

extension PersistentKeyProtocolTests {
    // MARK: Tests
    
    func test_registerDefault() {
        let defaultValue: String = UUID().uuidString
        let key = PersistentKey(UUID().uuidString, defaultValue: defaultValue)
        
        var dictionary: [String: Any] = [:]
        
        type(of: defaultValue).persistentKeyValueRepresentation.set(key.id, to: defaultValue, in: &dictionary)
        
        key.registerDefault(in: &dictionary)
        
        XCTAssertEqual(dictionary[key.id] as? String, defaultValue)
    }
}
