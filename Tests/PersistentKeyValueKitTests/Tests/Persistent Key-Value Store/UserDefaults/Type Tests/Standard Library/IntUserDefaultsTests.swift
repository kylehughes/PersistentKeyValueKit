//
//  IntUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class IntUserDefaultsTests: AbstractUserDefaultsTypeTests<Int> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [Int] {
        [
            .max,
            .min,
            .zero,
        ]
    }

    // MARK: Tests

    func test_get_argumentDomainString() {
        let key = PersistentKey("IntArgument", defaultValue: 0)

        store.setVolatileDomain([key.id: "42"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), 42)
    }

    func test_get_argumentDomainString_invalidValueReturnsDefaultValue() {
        let key = PersistentKey("IntArgument", defaultValue: 7)

        store.setVolatileDomain([key.id: "not an integer"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), 7)
    }
}
