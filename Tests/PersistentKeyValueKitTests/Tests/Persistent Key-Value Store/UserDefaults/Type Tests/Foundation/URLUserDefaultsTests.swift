//
//  URLUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class URLUserDefaultsTests: AbstractUserDefaultsTypeTests<URL> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override var testValues: [URL] {
        [
            URL(string: "https://kylehugh.es")!,
            URL(string: "https://example.com/path?query=value#fragment")!,
            URL(string: "file:///path/to/file.txt")!,
            URL(string: "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==")!,
        ]
    }

    // MARK: Tests

    func test_get_argumentDomainString() {
        let key = PersistentKey("URLArgument", defaultValue: URL(string: "https://default.example.com")!)
        let expectedValue = URL(string: "https://example.com/path?query=value#fragment")!

        store.setVolatileDomain([key.id: expectedValue.absoluteString], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), expectedValue)
    }

    func test_get_argumentDomainString_invalidValueReturnsDefaultValue() {
        let defaultValue = URL(string: "https://default.example.com")!
        let key = PersistentKey("URLArgument", defaultValue: defaultValue)

        store.setVolatileDomain([key.id: "not a valid url"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(store.get(key), defaultValue)
    }
}
