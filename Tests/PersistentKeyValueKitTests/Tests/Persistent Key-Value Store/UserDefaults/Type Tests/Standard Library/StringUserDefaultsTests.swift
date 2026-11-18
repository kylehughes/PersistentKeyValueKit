//
//  StringUserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class StringUserDefaultsTests: AbstractUserDefaultsTypeTests<String> {
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

    func test_decode_userDefaultsNumberMatchesStringForKey() throws {
        let numbers: [NSNumber] = [
            NSNumber(value: 42),
            NSNumber(value: Int32(-7)),
            NSNumber(value: Int64.max),
            NSNumber(value: Int64.min),
            NSNumber(value: UInt64.max),
            NSNumber(value: 1.0),
            NSNumber(value: 0.1),
            NSNumber(value: 1.0 / 3.0),
            NSNumber(value: 1e300),
            NSNumber(value: -0.0),
            NSNumber(value: Double.nan),
            NSNumber(value: -Double.infinity),
            NSNumber(value: Float(1.1)),
            NSNumber(value: true),
            NSNumber(value: false),
            NSDecimalNumber(string: "7.6659877654567334223"),
        ]

        for (index, number) in numbers.enumerated() {
            let key = PersistentKey("key:\(#function).\(index)", defaultValue: "fallback")

            store.set(number, forKey: key.id)

            let stored = try XCTUnwrap(store.object(forKey: key.id))
            let expected = try XCTUnwrap(store.string(forKey: key.id), "\(number)")

            XCTAssertEqual(try String.decode(storageObject: stored, format: .userDefaults), expected, "\(number)")
            XCTAssertEqual(store.get(key), expected, "\(number)")
        }

        XCTAssertEqual(try String.decode(storageObject: NSNumber(value: true), format: .userDefaults), "1")
        XCTAssertEqual(try String.decode(storageObject: NSNumber(value: false), format: .userDefaults), "0")
    }

    func test_decode_numberThrowsInPropertyListFormat() {
        XCTAssertThrowsError(try String.decode(storageObject: NSNumber(value: 42), format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }

        XCTAssertThrowsError(try String.decode(storageObject: Data([52, 50]), format: .userDefaults))
    }

    func test_move_storedNumberToStringKeyMovesItsString() throws {
        let sourceName = stableSuiteName("StringUserDefaultsTests.numberSource", function: name)
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: sourceName))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "fallback")

        defer {
            source.removePersistentDomain(forName: sourceName)
        }

        source.set(42, forKey: key.id)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertEqual(destination.get(key), "42")
        XCTAssertNil(source.object(forKey: key.id))
    }
}
