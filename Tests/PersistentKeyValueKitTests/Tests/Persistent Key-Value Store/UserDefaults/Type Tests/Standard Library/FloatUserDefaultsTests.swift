//
//  FloatUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class FloatUserDefaultsTests: AbstractUserDefaultsTypeTests<Float> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Float] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }

    // MARK: Tests

    func test_get_argumentDomainString() {
        let key = PersistentKey("FloatArgument", defaultValue: Float(0))

        store.setVolatileDomain([key.id: "3.25"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), Float(3.25))
    }

    func test_get_argumentDomainString_invalidValueReturnsDefaultValue() {
        let key = PersistentKey("FloatArgument", defaultValue: Float(7.5))

        store.setVolatileDomain([key.id: "not a float"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), Float(7.5))
    }
}
