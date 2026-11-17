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
        suiteName = stableSuiteName("PersistentKeyValueKitTests.PrimitiveDefaults", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        // The argument domain is volatile process state. Clear it so launch-argument overrides do not leak.
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults = nil
        suiteName = nil
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

@available(watchOS 9.0, *)
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
}
