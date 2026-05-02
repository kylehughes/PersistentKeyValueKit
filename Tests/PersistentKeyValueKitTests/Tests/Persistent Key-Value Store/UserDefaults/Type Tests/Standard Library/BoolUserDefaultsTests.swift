//
//  BoolUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class BoolUserDefaultsTests: AbstractUserDefaultsTypeTests<Bool> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Bool] {
        [
            true,
            false
        ]
    }

    // MARK: Tests

    func test_get_argumentDomainString_falseValues() {
        let key = PersistentKey("BoolArgument", defaultValue: true)

        for value in ["0", "false", "FALSE", "no", "NO"] {
            store.setVolatileDomain([key.id: value], forName: UserDefaults.argumentDomain)

            XCTAssertFalse(store.get(key), value)
        }
    }

    func test_get_argumentDomainString_invalidValueReturnsDefaultValue() {
        let key = PersistentKey("BoolArgument", defaultValue: true)

        store.setVolatileDomain([key.id: "maybe"], forName: UserDefaults.argumentDomain)

        XCTAssertTrue(store.get(key))
    }

    func test_get_argumentDomainString_invalidValueShadowsStoredValue() {
        let key = PersistentKey("BoolArgument", defaultValue: true)

        store.set(key, to: false)
        store.setVolatileDomain([key.id: "maybe"], forName: UserDefaults.argumentDomain)

        XCTAssertTrue(store.get(key))
    }

    func test_get_persistedString_isNotCoerced() {
        let key = PersistentKey("BoolArgument", defaultValue: true)

        store.set("false", forKey: key.id)

        XCTAssertTrue(store.get(key))
    }

    func test_get_argumentDomainString_trueValues() {
        let key = PersistentKey("BoolArgument", defaultValue: false)

        for value in ["1", "true", "TRUE", "yes", "YES"] {
            store.setVolatileDomain([key.id: value], forName: UserDefaults.argumentDomain)

            XCTAssertTrue(store.get(key), value)
        }
    }
}
