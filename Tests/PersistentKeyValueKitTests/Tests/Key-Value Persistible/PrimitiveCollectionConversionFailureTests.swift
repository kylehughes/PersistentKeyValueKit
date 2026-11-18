//
//  PrimitiveCollectionConversionFailureTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies how arrays and dictionaries handle elements that fail to convert.
///
/// A collection write commits only when every element encodes, so one unencodable element leaves the stored collection
/// in place instead of replacing it with the elements that did encode. An array read returns the key's default when
/// any element fails to decode, because positions can carry meaning. A dictionary read keeps every entry that decodes
/// and omits the rest, because entries are independent. Checked migration rejects either collection when any element
/// fails to decode. `nil` elements of collections of optionals are omitted on write, because they are not conversion
/// failures.
final class PrimitiveCollectionConversionFailureTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.PrimitiveCollectionConversionFailure", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Array Write Tests

    func test_set_array_codableElementFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [CodablePayload]()),
            stored: [CodablePayload(10)],
            failing: [CodablePayload(20), CodablePayload(.nan)]
        )
    }

    func test_set_array_representationElementFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [ThrowingPayload]()),
            stored: [ThrowingPayload(10)],
            failing: [ThrowingPayload(20), ThrowingPayload(-1)]
        )
    }

    func test_set_arrayOfArrays_elementFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [[CodablePayload]]()),
            stored: [[CodablePayload(10)]],
            failing: [[CodablePayload(20)], [CodablePayload(.nan)]]
        )
    }

    func test_set_arrayOfDictionaries_valueFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [[String: CodablePayload]]()),
            stored: [["a": CodablePayload(10)]],
            failing: [["a": CodablePayload(20)], ["b": CodablePayload(.nan)]]
        )
    }

    func test_set_arrayOfOptionals_elementFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [CodablePayload?]()),
            stored: [CodablePayload(10)],
            failing: [CodablePayload(20), nil, CodablePayload(.nan)]
        )
    }

    func test_set_arrayOfOptionals_omitsNilElements() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [CodablePayload?]()),
            value: [CodablePayload(20), nil, CodablePayload(30)],
            readsBack: [CodablePayload(20), CodablePayload(30)]
        )
    }

    func test_set_arrayOfProxies_conversionFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey(
                "key:\(#function)",
                defaultValue: [Int](),
                representation: ProxyPersistentKeyValueRepresentation<[Int], [String]>(
                    to: { values in
                        values.allSatisfy { $0 >= 0 } ? values.map(String.init) : nil
                    },
                    from: { strings in
                        strings.compactMap(Int.init)
                    }
                )
            ),
            stored: [10],
            failing: [20, -1]
        )
    }

    func test_set_arrayOfProxiesToOptionals_omitsNilProxies() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [OptionalProxyPayload]()),
            value: [OptionalProxyPayload(20), OptionalProxyPayload(nil), OptionalProxyPayload(30)],
            readsBack: [OptionalProxyPayload(20), OptionalProxyPayload(30)]
        )
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [OptionalProxyPayload(10)]),
            value: [OptionalProxyPayload(nil), OptionalProxyPayload(nil)],
            readsBack: [OptionalProxyPayload]()
        )
    }

    func test_set_arrayOfProxiesToOptionals_conversionFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [OptionalProxyPayload]()),
            stored: [OptionalProxyPayload(10)],
            failing: [OptionalProxyPayload(nil), OptionalProxyPayload(-1)]
        )
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [OptionalProxyPayload]()),
            stored: [OptionalProxyPayload(10)],
            failing: [OptionalProxyPayload(20), OptionalProxyPayload(-1)]
        )
    }

    func test_set_optionalArray_elementFails_leavesStoredArray() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey<[CodablePayload]?>("key:\(#function)", defaultValue: nil),
            stored: [CodablePayload(10)],
            failing: [CodablePayload(20), CodablePayload(.nan)]
        )
    }

    // MARK: Dictionary Write Tests

    func test_set_dictionary_valueFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: CodablePayload]()),
            stored: ["old": CodablePayload(10)],
            failing: ["good": CodablePayload(20), "bad": CodablePayload(.nan)]
        )
    }

    func test_set_dictionary_representationValueFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: ThrowingPayload]()),
            stored: ["old": ThrowingPayload(10)],
            failing: ["good": ThrowingPayload(20), "bad": ThrowingPayload(-1)]
        )
    }

    func test_set_dictionaryOfArrays_elementFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: [CodablePayload]]()),
            stored: ["old": [CodablePayload(10)]],
            failing: ["good": [CodablePayload(20)], "bad": [CodablePayload(.nan)]]
        )
    }

    func test_set_dictionaryOfOptionals_omitsNilValues() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [String: CodablePayload?]()),
            value: ["a": CodablePayload(20), "b": nil],
            readsBack: ["a": CodablePayload(20)]
        )
    }

    func test_set_dictionaryOfOptionals_valueFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: CodablePayload?]()),
            stored: ["old": CodablePayload(10)],
            failing: ["good": CodablePayload(20), "nil": nil, "bad": CodablePayload(.nan)]
        )
    }

    func test_set_dictionaryOfProxies_proxyFailsToEncode_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: ProxiedThrowingPayload]()),
            stored: ["old": ProxiedThrowingPayload(10)],
            failing: ["good": ProxiedThrowingPayload(20), "bad": ProxiedThrowingPayload(-1)]
        )
    }

    func test_set_dictionaryOfProxiesToOptionals_omitsNilProxies() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [String: OptionalProxyPayload]()),
            value: ["a": OptionalProxyPayload(20), "b": OptionalProxyPayload(nil)],
            readsBack: ["a": OptionalProxyPayload(20)]
        )
    }

    func test_set_dictionaryOfProxiesToOptionals_conversionFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: OptionalProxyPayload]()),
            stored: ["old": OptionalProxyPayload(10)],
            failing: ["bad": OptionalProxyPayload(-1)]
        )
    }

    func test_set_dictionaryOfOptionalProxiesToOptionals_omitsNilValuesAndNilProxies() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [String: OptionalProxyPayload?]()),
            value: ["a": OptionalProxyPayload(20), "b": nil, "c": OptionalProxyPayload(nil)],
            readsBack: ["a": OptionalProxyPayload(20)]
        )
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: ["old": Optional(OptionalProxyPayload(10))]),
            value: ["b": nil, "c": OptionalProxyPayload(nil)],
            readsBack: [String: OptionalProxyPayload]()
        )
    }

    func test_set_dictionaryOfOptionalProxiesToOptionals_conversionFails_leavesStoredDictionary() {
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [String: OptionalProxyPayload?]()),
            stored: ["old": OptionalProxyPayload(10)],
            failing: ["good": OptionalProxyPayload(20), "nil": nil, "bad": OptionalProxyPayload(-1)]
        )
    }

    func test_set_arrayOfArraysOfOptionals_omitsNilElementsAndLeavesStoredArrayOnFailure() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [[CodablePayload?]]()),
            value: [[CodablePayload(20), nil], [nil]],
            readsBack: [[CodablePayload(20)], []]
        )
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [[CodablePayload?]]()),
            stored: [[CodablePayload(10)]],
            failing: [[nil], [CodablePayload(.nan)]]
        )
    }

    func test_set_arrayOfDictionariesOfOptionals_omitsNilValuesAndLeavesStoredArrayOnFailure() {
        assertWrite(
            PersistentKey("key:\(#function)", defaultValue: [[String: CodablePayload?]]()),
            value: [["a": CodablePayload(20), "b": nil], ["c": nil]],
            readsBack: [["a": CodablePayload(20)], [:]]
        )
        assertFailedWriteLeavesStoredValue(
            PersistentKey("key:\(#function)", defaultValue: [[String: CodablePayload?]]()),
            stored: [["old": CodablePayload(10)]],
            failing: [["a": nil], ["b": CodablePayload(.nan)]]
        )
    }

    // MARK: Property-List Container Tests

    func test_propertyListDictionary_arrayElementFails_leavesDictionaryUnchanged() {
        let representation = [CodablePayload].persistentKeyValueRepresentation
        var dictionary: [String: Any] = ["key": "stale"]

        representation.set("key", to: [CodablePayload(20), CodablePayload(.nan)], in: &dictionary)

        XCTAssertEqual(dictionary["key"] as? String, "stale")
    }

    func test_propertyListDictionary_dictionaryValueFails_leavesDictionaryUnchanged() {
        let representation = [String: CodablePayload].persistentKeyValueRepresentation
        var dictionary: [String: Any] = ["key": "stale"]

        representation.set("key", to: ["good": CodablePayload(20), "bad": CodablePayload(.nan)], in: &dictionary)

        XCTAssertEqual(dictionary["key"] as? String, "stale")
    }

    func test_propertyListArray_dictionaryValueFailsToDecode_omitsEntry() {
        let representation = [String: Shape].persistentKeyValueRepresentation

        XCTAssertEqual(
            representation.get(from: [["a": "circle", "b": "hexagon"], ["c": "square"]]),
            [["a": .circle], ["c": .square]]
        )
        XCTAssertNil(representation.get(from: [["a": "circle"], "not a dictionary"]))
    }

    func test_propertyListDictionary_dictionaryValueFailsToDecode_omitsEntry() {
        let representation = [String: Shape].persistentKeyValueRepresentation

        XCTAssertEqual(representation.get("key", from: ["key": ["a": "circle", "b": "hexagon"]]), ["a": .circle])
        XCTAssertNil(representation.get("key", from: ["key": "not a dictionary"]))
    }

    // MARK: Read Tests

    func test_get_array_elementFailsToDecode_returnsDefaultValue() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [Shape.square])

        try assertRead(key, stored: ["circle", "hexagon"], readsBack: [.square])
        try assertRead(key, stored: ["circle"], readsBack: [.circle])
    }

    func test_get_arrayOfDictionaries_valueFailsToDecode_omitsEntry() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [["default": Shape.square]])
        let stored: [Any] = [["a": "circle"], ["b": "hexagon", "c": "square"]]

        try assertRead(key, stored: stored, readsBack: [["a": .circle], ["c": .square]])
    }

    func test_get_dictionary_valueFailsToDecode_omitsEntry() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: ["default": Shape.square])

        try assertRead(key, stored: ["a": "circle", "b": "hexagon"], readsBack: ["a": .circle])
        try assertRead(key, stored: ["b": "hexagon"], readsBack: [:])
    }

    func test_get_dictionaryOfOptionals_valueFailsToDecode_omitsEntry() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: ["default": Shape?.some(.square)])

        try assertRead(key, stored: ["a": "circle", "b": "hexagon"], readsBack: ["a": .circle])
    }

    func test_get_optionalDictionary_valueFailsToDecode_omitsEntry() throws {
        let key = PersistentKey<[String: Shape]?>("key:\(#function)", defaultValue: nil)

        try assertRead(key, stored: ["a": "circle", "b": "hexagon"], readsBack: ["a": .circle])
    }

    func test_get_proxyOverDictionary_valueFailsToDecode_omitsEntry() throws {
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: Set<Shape>(),
            representation: ProxyPersistentKeyValueRepresentation<Set<Shape>, [String: Shape]>(
                to: { shapes in
                    Dictionary(uniqueKeysWithValues: shapes.map { ($0.rawValue, $0) })
                },
                from: { dictionary in
                    Set(dictionary.values)
                }
            )
        )

        try assertRead(key, stored: ["circle": "circle", "hexagon": "hexagon"], readsBack: [.circle])
    }

    func test_readModifyWrite_dictionaryWithUndecodableEntry_keepsReadableEntries() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [String: Shape]())
        let ubiquitousStore = MockUbiquitousKeyValueStore()
        let stored: [String: Any] = ["a": "circle", "b": "hexagon", "c": "square"]

        for store in [userDefaults as any PersistentKeyValueStore, ubiquitousStore] {
            userDefaults.set(stored, forKey: key.id)
            ubiquitousStore.set(stored, forKey: key.id)

            var shapes = store.get(key)
            shapes["d"] = .circle
            store.set(key, to: shapes)

            XCTAssertEqual(store.get(key), ["a": .circle, "c": .square, "d": .circle], "\(type(of: store))")
        }
    }

    // MARK: Migration Tests

    func test_migration_dictionaryValueFailsToDecode_failsAtDecodeAndKeepsSource() throws {
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: [String: Shape]())
        let stored: [String: Any] = ["a": "circle", "b": "hexagon"]

        source.set(stored, forKey: key.id)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.first?.status, .failed(.decode))
        XCTAssertEqual(source.dictionary(forKey: key.id) as? [String: String], ["a": "circle", "b": "hexagon"])
        XCTAssertNil(destination.object(forKey: key.id))
    }

    // MARK: Private Instance Interface

    private func assertFailedWriteLeavesStoredValue<Value>(
        _ key: PersistentKey<Value>,
        stored: Value,
        failing: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where Value: Equatable {
        let ubiquitousStore = MockUbiquitousKeyValueStore()

        for store in [userDefaults as any PersistentKeyValueStore, ubiquitousStore] {
            store.set(key, to: stored)
            store.set(key, to: failing)

            XCTAssertEqual(store.get(key), stored, "\(type(of: store))", file: file, line: line)
        }
    }

    private func assertRead<Value>(
        _ key: PersistentKey<Value>,
        stored: Any,
        readsBack expected: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Value: Equatable {
        let ubiquitousStore = MockUbiquitousKeyValueStore()

        userDefaults.set(stored, forKey: key.id)
        ubiquitousStore.set(stored, forKey: key.id)

        XCTAssertEqual(userDefaults.get(key), expected, "UserDefaults", file: file, line: line)
        XCTAssertEqual(ubiquitousStore.get(key), expected, "NSUbiquitousKeyValueStore", file: file, line: line)
    }

    private func assertWrite<Value, Expected>(
        _ key: PersistentKey<Value>,
        value: Value,
        readsBack expected: Expected,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where Value: Equatable, Expected: Equatable & KeyValuePersistible & Sendable {
        let ubiquitousStore = MockUbiquitousKeyValueStore()
        let expectedKey = PersistentKey(key.id, defaultValue: expected)

        for store in [userDefaults as any PersistentKeyValueStore, ubiquitousStore] {
            store.set(key, to: value)

            XCTAssertEqual(store.get(expectedKey), expected, "\(type(of: store))", file: file, line: line)
        }
    }
}

// MARK: - Private Types

private struct CodablePayload: Codable, Equatable, KeyValuePersistible {
    let number: Double

    init(_ number: Double) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: CodablePersistentKeyValueRepresentation<Self, JSONEncoder, JSONDecoder> {
        CodablePersistentKeyValueRepresentation()
    }
}

/// A value stored through a proxy to an optional: a `nil` number converts to a `nil` proxy, which collections omit, and
/// a negative number fails to convert.
private struct OptionalProxyPayload: Equatable, KeyValuePersistible {
    let number: Int?

    init(_ number: Int?) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, Int?> {
        ProxyPersistentKeyValueRepresentation(
            to: { value -> Int?? in
                guard let number = value.number else {
                    return .some(nil)
                }

                guard number >= 0 else {
                    return .none
                }

                return number
            },
            from: { proxy in
                OptionalProxyPayload(proxy)
            }
        )
    }
}

/// A value stored through a built-in proxy whose conversion always succeeds, to a representation that fails to encode a
/// negative number.
private struct ProxiedThrowingPayload: Equatable, KeyValuePersistible {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, ThrowingPayload> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                ThrowingPayload($0.number)
            },
            from: {
                ProxiedThrowingPayload($0.number)
            }
        )
    }
}

private enum Shape: String, Equatable, KeyValuePersistible {
    case circle
    case square

    static var persistentKeyValueRepresentation: RawRepresentablePersistentKeyValueRepresentation<Self> {
        RawRepresentablePersistentKeyValueRepresentation()
    }
}

/// A value whose representation implements only the required conversions and throws for negative values.
private struct ThrowingPayload: Equatable, KeyValuePersistible {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: ThrowingPayloadRepresentation {
        ThrowingPayloadRepresentation()
    }
}

private struct ThrowingPayloadRepresentation: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> ThrowingPayload {
        guard let number = storageObject as? Int else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return ThrowingPayload(number)
    }

    func encode(_ value: ThrowingPayload, format: PersistentKeyValueStorageFormat) throws -> Any? {
        guard value.number >= 0 else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return value.number
    }
}
