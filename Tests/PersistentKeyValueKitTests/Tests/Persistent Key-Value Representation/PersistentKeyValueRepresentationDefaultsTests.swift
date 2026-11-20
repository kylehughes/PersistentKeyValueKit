//
//  PersistentKeyValueRepresentationDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyValueRepresentationDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.RepresentationDefaults", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        // The argument domain is volatile process state. Clear it so launch-argument overrides do not leak.
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    private var representation: ConversionOnlyPersistentKeyValueRepresentation {
        ConversionOnlyPersistentKeyValueRepresentation()
    }
}

// MARK: - Property List Array Tests

extension PersistentKeyValueRepresentationDefaultsTests {
    func test_getFromArray_decodesEveryElement() {
        XCTAssertEqual(representation.get(from: [1, 2, 3]), [.init(1), .init(2), .init(3)])
        XCTAssertEqual(representation.get(from: []), [])
    }

    func test_getFromArray_returnsNilWhenAnyElementFailsToDecode() {
        XCTAssertNil(representation.get(from: [1, "2", 3]))
    }

    func test_setToArray_assignsEncodedElementsAndDropsRemovedElements() {
        var array: [Any] = ["existing"]

        representation.set([.init(4), .init(0), .init(5)], to: &array)

        XCTAssertEqual(array as? [Int], [4, 5])
    }

    func test_setToArray_leavesArrayUnchangedWhenAnyElementThrows() {
        var array: [Any] = ["existing"]

        representation.set([.init(4), .init(-1), .init(5)], to: &array)

        XCTAssertEqual(array as? [String], ["existing"])
    }
}

// MARK: - Property List Dictionary Tests

extension PersistentKeyValueRepresentationDefaultsTests {
    func test_getFromDictionary() {
        let dictionary: [String: Any] = ["valid": 6, "invalid": "6"]

        XCTAssertEqual(representation.get("valid", from: dictionary), .init(6))
        XCTAssertNil(representation.get("invalid", from: dictionary))
        XCTAssertNil(representation.get("absent", from: dictionary))
    }

    func test_setInDictionary() {
        var dictionary: [String: Any] = ["removed": 1, "unchanged": 2]

        representation.set("written", to: .init(7), in: &dictionary)
        representation.set("removed", to: .init(0), in: &dictionary)
        representation.set("unchanged", to: .init(-1), in: &dictionary)

        XCTAssertEqual(dictionary as? [String: Int], ["written": 7, "unchanged": 2])
    }
}

// MARK: - User Defaults Tests

extension PersistentKeyValueRepresentationDefaultsTests {
    func test_getFromUserDefaults() {
        userDefaults.set(8, forKey: "valid")
        userDefaults.set("8", forKey: "invalid")

        XCTAssertEqual(representation.get("valid", from: userDefaults), .init(8))
        XCTAssertNil(representation.get("invalid", from: userDefaults))
        XCTAssertNil(representation.get("absent", from: userDefaults))
    }

    func test_getFromUserDefaults_doesNotCoerceArgumentDomainStrings() {
        let key = PersistentKey("key:\(#function)", defaultValue: ConversionOnlyValue(99))

        userDefaults.setVolatileDomain([key.id: "8"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(userDefaults.get(key), .init(99))
    }

    func test_setInUserDefaults() {
        userDefaults.set(1, forKey: "removed")
        userDefaults.set(2, forKey: "unchanged")

        representation.set("written", to: .init(9), in: userDefaults)
        representation.set("removed", to: .init(0), in: userDefaults)
        representation.set("unchanged", to: .init(-1), in: userDefaults)

        XCTAssertEqual(userDefaults.object(forKey: "written") as? Int, 9)
        XCTAssertNil(userDefaults.object(forKey: "removed"))
        XCTAssertEqual(userDefaults.object(forKey: "unchanged") as? Int, 2)
    }

    func test_userDefaults_keyRoundTripsScalarsArraysAndDictionaries() {
        let scalarKey = PersistentKey("key:\(#function).scalar", defaultValue: ConversionOnlyValue(1))
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [ConversionOnlyValue]())
        let optionalArrayKey = PersistentKey("key:\(#function).optionalArray", defaultValue: [ConversionOnlyValue?]())
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: ConversionOnlyValue]())

        userDefaults.set(scalarKey, to: .init(2))
        userDefaults.set(arrayKey, to: [.init(3), .init(4)])
        userDefaults.set(optionalArrayKey, to: [.init(5), nil, .init(6)])
        userDefaults.set(dictionaryKey, to: ["a": .init(7)])
        // A dictionary whose custom value encodes to `nil` is indistinguishable from a failed write.
        userDefaults.set(dictionaryKey, to: ["a": .init(8), "removed": .init(0)])

        XCTAssertEqual(userDefaults.get(scalarKey), .init(2))
        XCTAssertEqual(userDefaults.get(arrayKey), [.init(3), .init(4)])
        XCTAssertEqual(userDefaults.get(optionalArrayKey), [.init(5), .init(6)])
        XCTAssertEqual(userDefaults.get(dictionaryKey), ["a": .init(7)])

        userDefaults.set(scalarKey, to: .init(0))

        XCTAssertNil(userDefaults.object(forKey: scalarKey.id))
        XCTAssertEqual(userDefaults.get(scalarKey), .init(1))
    }
}

// MARK: - Ubiquitous Key-Value Store Tests

extension PersistentKeyValueRepresentationDefaultsTests {
    func test_getFromUbiquitousStore() {
        let store = MockUbiquitousKeyValueStore()

        store.set(10, forKey: "valid")
        store.set("10", forKey: "invalid")

        XCTAssertEqual(representation.get("valid", from: store), .init(10))
        XCTAssertNil(representation.get("invalid", from: store))
        XCTAssertNil(representation.get("absent", from: store))
    }

    func test_setInUbiquitousStore() {
        let store = MockUbiquitousKeyValueStore()

        store.set(1, forKey: "removed")
        store.set(2, forKey: "unchanged")

        representation.set("written", to: .init(11), in: store)
        representation.set("removed", to: .init(0), in: store)
        representation.set("unchanged", to: .init(-1), in: store)

        XCTAssertEqual(store.object(forKey: "written") as? Int, 11)
        XCTAssertNil(store.object(forKey: "removed"))
        XCTAssertEqual(store.object(forKey: "unchanged") as? Int, 2)
    }

    func test_writes_leaveStoresUnchangedWhenEncodeReturnsNonPropertyList() {
        let invalid = ConversionOnlyValue(conversionOnlyNonPropertyListRawValue)
        let ubiquitousStore = MockUbiquitousKeyValueStore()
        var array: [Any] = [1]
        var dictionary: [String: Any] = ["key": 1]

        userDefaults.set(1, forKey: "key")
        ubiquitousStore.set(1, forKey: "key")

        representation.set([.init(2), invalid], to: &array)
        representation.set("key", to: invalid, in: &dictionary)
        representation.set("key", to: invalid, in: userDefaults)
        representation.set("key", to: invalid, in: ubiquitousStore)

        XCTAssertEqual(array as? [Int], [1])
        XCTAssertEqual(dictionary["key"] as? Int, 1)
        XCTAssertEqual(userDefaults.object(forKey: "key") as? Int, 1)
        XCTAssertEqual(ubiquitousStore.object(forKey: "key") as? Int, 1)
    }
}

// MARK: - Witness Resolution Tests

extension PersistentKeyValueRepresentationDefaultsTests {
    func test_proxyRepresentation_userDefaultsGetKeepsArgumentDomainCoercion() {
        let representation = ProxyPersistentKeyValueRepresentation<ConversionOnlyValue, Int>(
            to: \.rawValue,
            from: ConversionOnlyValue.init
        )
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: ConversionOnlyValue(0),
            representation: representation
        )

        userDefaults.setVolatileDomain([key.id: "12"], forName: UserDefaults.argumentDomain)

        // The base-protocol default would decode the `String` through `Int` and fail; the proxy-protocol
        // implementation forwards to `Int`'s launch-argument coercion.
        XCTAssertEqual(userDefaults.get(key), .init(12))
        XCTAssertEqual(genericGet(key.id, from: userDefaults, using: representation), .init(12))
        XCTAssertEqual(
            genericGet(key.id, from: userDefaults, using: representation.optionalRepresentation),
            .some(.init(12))
        )
    }

    func test_rawRepresentableRepresentation_userDefaultsGetKeepsArgumentDomainCoercion() {
        let key = PersistentKey("key:\(#function)", defaultValue: WitnessResolutionMode.off)

        userDefaults.setVolatileDomain([key.id: "1"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(userDefaults.get(key), .on)
    }

    func test_primitiveRepresentation_userDefaultsGetKeepsArgumentDomainCoercion() {
        userDefaults.setVolatileDomain(["key": "14"], forName: UserDefaults.argumentDomain)

        XCTAssertEqual(genericGet("key", from: userDefaults, using: Int.persistentKeyValueRepresentation), 14)
        XCTAssertEqual(genericPrimitiveGet("key", from: userDefaults, as: Int.self), 14)
    }

    // MARK: Private Instance Interface

    private func genericGet<Representation: PersistentKeyValueRepresentation>(
        _ key: String,
        from userDefaults: UserDefaults,
        using representation: Representation
    ) -> Representation.Value? {
        representation.get(key, from: userDefaults)
    }

    private func genericPrimitiveGet<Value: PrimitiveKeyValuePersistible>(
        _ key: String,
        from userDefaults: UserDefaults,
        as type: Value.Type
    ) -> Value? {
        Value.get(key, from: userDefaults)
    }

}

// MARK: - Witness Resolution Mode Definition

private enum WitnessResolutionMode: Int, KeyValuePersistible {
    case off
    case on

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}
