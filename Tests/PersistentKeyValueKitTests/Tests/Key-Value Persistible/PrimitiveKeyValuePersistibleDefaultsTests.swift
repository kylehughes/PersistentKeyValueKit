//
//  PrimitiveKeyValuePersistibleDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class PrimitiveKeyValuePersistibleDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        (userDefaults, suiteName) = try makeStableUserDefaults(
            "PersistentKeyValueKitTests.PrimitiveDefaults",
            function: name
        )
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        // The argument domain is volatile process state. Clear it so launch-argument overrides do not leak.
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults = nil
        suiteName = nil
    }
}

// MARK: - Property List Array Tests

extension PrimitiveKeyValuePersistibleDefaultsTests {
    func test_getFromArray_decodesEveryElement() {
        XCTAssertEqual(ConversionOnlyPrimitive.get(from: [1, 2]), [.init(1), .init(2)])
        XCTAssertEqual(ConversionOnlyPrimitive.get(from: []), [])
    }

    func test_getFromArray_returnsNilWhenAnyElementFailsToDecode() {
        XCTAssertNil(ConversionOnlyPrimitive.get(from: [1, "2"]))
    }

    func test_setToArray_assignsEncodedObjectsAndDropsRemovedElements() {
        var array: [Any] = ["existing"]

        ConversionOnlyPrimitive.set([.init(3), .init(0), .init(4)], to: &array)

        // The encoded `Int` objects are stored, not `ConversionOnlyPrimitive` values.
        XCTAssertEqual(array as? [Int], [3, 4])
    }

    func test_setToArray_leavesArrayUnchangedWhenAnyElementThrows() {
        var array: [Any] = ["existing"]

        ConversionOnlyPrimitive.set([.init(3), .init(-1)], to: &array)

        XCTAssertEqual(array as? [String], ["existing"])
    }
}

// MARK: - Property List Dictionary Tests

extension PrimitiveKeyValuePersistibleDefaultsTests {
    func test_getFromDictionary() {
        let dictionary: [String: Any] = ["valid": 5, "invalid": "5"]

        XCTAssertEqual(ConversionOnlyPrimitive.get("valid", from: dictionary), .init(5))
        XCTAssertNil(ConversionOnlyPrimitive.get("invalid", from: dictionary))
        XCTAssertNil(ConversionOnlyPrimitive.get("absent", from: dictionary))
    }

    func test_setInDictionary() {
        var dictionary: [String: Any] = ["removed": 1, "unchanged": 2]

        ConversionOnlyPrimitive.set("written", to: .init(6), in: &dictionary)
        ConversionOnlyPrimitive.set("removed", to: .init(0), in: &dictionary)
        ConversionOnlyPrimitive.set("unchanged", to: .init(-1), in: &dictionary)

        XCTAssertEqual(dictionary as? [String: Int], ["written": 6, "unchanged": 2])
    }

    func test_userDefaults_arrayAndDictionaryKeysStoreEncodedObjects() {
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [ConversionOnlyPrimitive]())
        let dictionaryKey = PersistentKey(
            "key:\(#function).dictionary",
            defaultValue: [String: ConversionOnlyPrimitive]()
        )

        userDefaults.set(arrayKey, to: [.init(7), .init(0), .init(8)])
        userDefaults.set(dictionaryKey, to: ["a": .init(9)])
        // A dictionary whose custom value encodes to `nil` is indistinguishable from a failed write.
        userDefaults.set(dictionaryKey, to: ["a": .init(10), "removed": .init(0)])

        XCTAssertEqual(userDefaults.object(forKey: arrayKey.id) as? [Int], [7, 8])
        XCTAssertEqual(userDefaults.object(forKey: dictionaryKey.id) as? [String: Int], ["a": 9])
        XCTAssertEqual(userDefaults.get(arrayKey), [.init(7), .init(8)])
        XCTAssertEqual(userDefaults.get(dictionaryKey), ["a": .init(9)])
    }
}

// MARK: - User Defaults Tests

extension PrimitiveKeyValuePersistibleDefaultsTests {
    func test_getFromUserDefaults() {
        userDefaults.set(1, forKey: "valid")
        userDefaults.set("1", forKey: "invalid")

        XCTAssertEqual(ConversionOnlyPrimitive.get("valid", from: userDefaults), .init(1))
        XCTAssertNil(ConversionOnlyPrimitive.get("invalid", from: userDefaults))
        XCTAssertNil(ConversionOnlyPrimitive.get("absent", from: userDefaults))
    }

    func test_getFromUserDefaults_doesNotCoerceArgumentDomainStrings() {
        let key = PersistentKey("key:\(#function)", defaultValue: ConversionOnlyPrimitive(99))

        userDefaults.setVolatileDomain([key.id: "2"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(userDefaults.get(key), .init(99))
    }

    func test_setInUserDefaults() {
        userDefaults.set(1, forKey: "removed")
        userDefaults.set(2, forKey: "unchanged")

        ConversionOnlyPrimitive.set("written", to: .init(3), in: userDefaults)
        ConversionOnlyPrimitive.set("removed", to: .init(0), in: userDefaults)
        ConversionOnlyPrimitive.set("unchanged", to: .init(-1), in: userDefaults)

        XCTAssertEqual(userDefaults.object(forKey: "written") as? Int, 3)
        XCTAssertNil(userDefaults.object(forKey: "removed"))
        XCTAssertEqual(userDefaults.object(forKey: "unchanged") as? Int, 2)
    }

    func test_userDefaults_keyRoundTrips() {
        let key = PersistentKey("key:\(#function)", defaultValue: ConversionOnlyPrimitive(1))

        userDefaults.set(key, to: .init(4))

        XCTAssertEqual(userDefaults.get(key), .init(4))
    }
}

// MARK: - Ubiquitous Key-Value Store Tests

extension PrimitiveKeyValuePersistibleDefaultsTests {
    func test_getFromUbiquitousStore() {
        let store = MockUbiquitousKeyValueStore()

        store.set(5, forKey: "valid")
        store.set("5", forKey: "invalid")

        XCTAssertEqual(ConversionOnlyPrimitive.get("valid", from: store), .init(5))
        XCTAssertNil(ConversionOnlyPrimitive.get("invalid", from: store))
        XCTAssertNil(ConversionOnlyPrimitive.get("absent", from: store))
    }

    func test_setInUbiquitousStore() {
        let store = MockUbiquitousKeyValueStore()

        store.set(1, forKey: "removed")
        store.set(2, forKey: "unchanged")

        ConversionOnlyPrimitive.set("written", to: .init(6), in: store)
        ConversionOnlyPrimitive.set("removed", to: .init(0), in: store)
        ConversionOnlyPrimitive.set("unchanged", to: .init(-1), in: store)

        XCTAssertEqual(store.object(forKey: "written") as? Int, 6)
        XCTAssertNil(store.object(forKey: "removed"))
        XCTAssertEqual(store.object(forKey: "unchanged") as? Int, 2)
    }

    func test_writes_leaveStoresUnchangedWhenEncodeReturnsNonPropertyList() {
        let invalid = ConversionOnlyPrimitive(conversionOnlyNonPropertyListRawValue)
        let ubiquitousStore = MockUbiquitousKeyValueStore()
        var array: [Any] = [1]
        var dictionary: [String: Any] = ["key": 1]

        userDefaults.set(1, forKey: "key")
        ubiquitousStore.set(1, forKey: "key")

        ConversionOnlyPrimitive.set([.init(2), invalid], to: &array)
        ConversionOnlyPrimitive.set("key", to: invalid, in: &dictionary)
        ConversionOnlyPrimitive.set("key", to: invalid, in: userDefaults)
        ConversionOnlyPrimitive.set("key", to: invalid, in: ubiquitousStore)

        XCTAssertEqual(array as? [Int], [1])
        XCTAssertEqual(dictionary["key"] as? Int, 1)
        XCTAssertEqual(userDefaults.object(forKey: "key") as? Int, 1)
        XCTAssertEqual(ubiquitousStore.object(forKey: "key") as? Int, 1)
    }
}
