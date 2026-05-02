//
//  DoubleUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class DoubleUserDefaultsTests: AbstractUserDefaultsTypeTests<Double> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Double] {
        [
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            .zero,
        ]
    }

    // MARK: Tests

    func test_get_argumentDomainString() {
        let key = PersistentKey("DoubleArgument", defaultValue: Double(0))

        store.setVolatileDomain([key.id: "3.25"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), 3.25)
    }

    func test_get_argumentDomainString_invalidValueReturnsDefaultValue() {
        let key = PersistentKey("DoubleArgument", defaultValue: 7.5)

        store.setVolatileDomain([key.id: "not a double"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), 7.5)
    }
}
