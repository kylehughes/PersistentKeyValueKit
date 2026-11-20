//
//  StringNSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class StringNSUbiquitousKeyValueStoreTests: AbstractNSUbiquitousKeyValueStoreTypeTests<String> {
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation

    override var testValues: [String] {
        [
            String(),
            "Created by Kyle Hughes on 5/11/24.",
            String(repeating: "A", count: 1_000),
            "Hello, 世界! 🌍",
        ]
    }

    // MARK: Tests

    func test_decode_ubiquitousNumberMatchesStringForKey() throws {
        let store = FoundationGetterUbiquitousStore()
        let numbers: [NSNumber] = [
            NSNumber(value: 123),
            NSNumber(value: Int64.min),
            NSNumber(value: UInt64.max),
            NSNumber(value: 0.125),
            NSNumber(value: -0.0),
            NSNumber(value: Float(1.1)),
            NSNumber(value: true),
            NSNumber(value: false),
        ]

        for (index, number) in numbers.enumerated() {
            let key = PersistentKey("key:\(#function).\(index)", defaultValue: "fallback")

            store.set(number, forKey: key.id)

            let stored = try XCTUnwrap(store.object(forKey: key.id))
            let expected = try XCTUnwrap(store.string(forKey: key.id), "\(number)")

            XCTAssertEqual(
                try String.decode(storageObject: stored, format: .ubiquitousKeyValueStore),
                expected,
                "\(number)"
            )
            XCTAssertEqual(store.get(key), expected, "\(number)")
        }

        XCTAssertEqual(try String.decode(storageObject: NSNumber(value: 123), format: .ubiquitousKeyValueStore), "123")
        XCTAssertThrowsError(try String.decode(storageObject: Data([49]), format: .ubiquitousKeyValueStore))
    }

    func test_move_storedNumberToStringKeyMovesItsString() throws {
        let source = FoundationGetterUbiquitousStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "fallback")

        source.set(NSNumber(value: 123), forKey: key.id)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertEqual(destination.get(key), "123")
        XCTAssertNil(source.object(forKey: key.id))
    }
}

// MARK: - Foundation Getter Ubiquitous Store Definition

/// An `NSUbiquitousKeyValueStore` with local storage that inherits Foundation's typed getters, such as
/// `string(forKey:)`, which read through `object(forKey:)`.
private final class FoundationGetterUbiquitousStore: NSUbiquitousKeyValueStore {
    private var values: [String: Any] = [:]

    // MARK: NSUbiquitousKeyValueStore Implementation

    override func object(forKey key: String) -> Any? {
        values[key]
    }

    override func set(_ object: Any?, forKey key: String) {
        values[key] = object
    }

    override func removeObject(forKey key: String) {
        values[key] = nil
    }
}
