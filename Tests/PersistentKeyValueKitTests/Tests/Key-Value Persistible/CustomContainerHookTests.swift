//
//  CustomContainerHookTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that every conversion path honors a representation's own property-list array hooks.
///
/// Ordinary reads and writes, registration, and checked conversion (which migration uses) must agree on the stored
/// form of an array. ``DeltaCodedTick`` stores an array differently from its elements, and ``AppendingToken`` appends
/// to the array it receives, as 1.x conformers did.
final class CustomContainerHookTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.CustomContainerHook", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    private var ticks: [DeltaCodedTick] {
        [DeltaCodedTick(10), DeltaCodedTick(13), DeltaCodedTick(20)]
    }

    private var tickDeltas: [Int] {
        [10, 3, 7]
    }
}

// MARK: - Delta-Coded Ordinary Access Tests

extension CustomContainerHookTests {
    func test_deltaCoded_setAndGet_storesArrayFormat() {
        let key = PersistentKey("key:\(#function)", defaultValue: [DeltaCodedTick]())
        let ubiquitousStore = MockUbiquitousKeyValueStore()

        userDefaults.set(key, to: ticks)
        ubiquitousStore.set(key, to: ticks)

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], tickDeltas)
        XCTAssertEqual(ubiquitousStore.array(forKey: key.id) as? [Int], tickDeltas)
        XCTAssertEqual(userDefaults.get(key), ticks)
        XCTAssertEqual(ubiquitousStore.get(key), ticks)
    }

    func test_deltaCoded_register_storesArrayFormat() {
        let key = PersistentKey("key:\(#function)", defaultValue: ticks)

        defer {
            userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        }

        userDefaults.register(key)

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], tickDeltas)
        XCTAssertEqual(userDefaults.get(key), ticks)
    }

    func test_deltaCoded_registerDefault_storesArrayFormat() {
        let key = PersistentKey("key:\(#function)", defaultValue: ticks)
        var defaults: [String: Any] = [:]

        key.registerDefault(in: &defaults)

        XCTAssertEqual(defaults[key.id] as? [Int], tickDeltas)
    }
}

// MARK: - Delta-Coded Checked Conversion Tests

extension CustomContainerHookTests {
    func test_deltaCoded_checkedDecode_usesArrayFormat() throws {
        let representation = [DeltaCodedTick].persistentKeyValueRepresentation

        for format in [PersistentKeyValueStorageFormat.propertyList, .userDefaults, .ubiquitousKeyValueStore] {
            XCTAssertEqual(try representation.decode(storageObject: tickDeltas, format: format), ticks, "\(format)")
        }
    }

    func test_deltaCoded_checkedEncode_usesArrayFormat() throws {
        let representation = [DeltaCodedTick].persistentKeyValueRepresentation

        for format in [PersistentKeyValueStorageFormat.propertyList, .userDefaults, .ubiquitousKeyValueStore] {
            XCTAssertEqual(try representation.encode(ticks, format: format) as? [Int], tickDeltas, "\(format)")
        }
    }

    func test_deltaCoded_checkedConversion_nestedContainersUseArrayFormat() throws {
        let nestedArray = [DeltaCodedTick?].persistentKeyValueRepresentation
        let arrayOfArrays = [[DeltaCodedTick]].persistentKeyValueRepresentation
        let dictionaryOfArrays = [String: [DeltaCodedTick]].persistentKeyValueRepresentation
        let optionalArray = PersistentKey<[DeltaCodedTick]?>("key:\(#function)", defaultValue: nil).representation

        let optionalTicks = ticks.map(Optional.some) + [nil]

        XCTAssertEqual(try nestedArray.decode(storageObject: tickDeltas, format: .propertyList), ticks)
        XCTAssertEqual(try nestedArray.encode(optionalTicks, format: .propertyList) as? [Int], tickDeltas)
        XCTAssertEqual(try arrayOfArrays.decode(storageObject: [tickDeltas], format: .propertyList), [ticks])
        XCTAssertEqual(try arrayOfArrays.encode([ticks], format: .propertyList) as? [[Int]], [tickDeltas])
        XCTAssertEqual(
            try dictionaryOfArrays.decode(storageObject: ["a": tickDeltas], format: .propertyList),
            ["a": ticks]
        )
        XCTAssertEqual(
            try dictionaryOfArrays.encode(["a": ticks], format: .propertyList) as? [String: [Int]],
            ["a": tickDeltas]
        )
        XCTAssertEqual(try optionalArray.decode(storageObject: tickDeltas, format: .userDefaults), ticks)
        XCTAssertEqual(try optionalArray.encode(ticks, format: .userDefaults) as? [Int], tickDeltas)
    }

    func test_deltaCoded_checkedDecode_invalidArrayThrows() {
        let representation = [DeltaCodedTick].persistentKeyValueRepresentation

        XCTAssertThrowsError(try representation.decode(storageObject: [10, "3"], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }
}

// MARK: - Delta-Coded Migration Tests

extension CustomContainerHookTests {
    func test_deltaCoded_moveFromUserDefaultsToMemory_deliversValues() throws {
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: [DeltaCodedTick]())

        source.set(key, to: ticks)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertEqual(destination.get(key), ticks)
    }

    func test_deltaCoded_moveFromMemoryToUserDefaults_storesArrayFormat() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let key = PersistentKey("key:\(#function)", defaultValue: [DeltaCodedTick]())

        source.set(key, to: ticks)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(destination.array(forKey: key.id) as? [Int], tickDeltas)
        XCTAssertEqual(destination.get(key), ticks)
    }
}

// MARK: - Appending Hook Tests

extension CustomContainerHookTests {
    func test_appending_set_replacesStoredArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [AppendingToken]())
        let ubiquitousStore = MockUbiquitousKeyValueStore()

        for store in [userDefaults as any PersistentKeyValueStore, ubiquitousStore] {
            store.set(key, to: [AppendingToken("red")])
            store.set(key, to: [AppendingToken("blue"), AppendingToken("green")])

            XCTAssertEqual(store.get(key), [AppendingToken("blue"), AppendingToken("green")], "\(type(of: store))")
        }

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [String], ["blue", "green"])
    }

    func test_appending_set_emptyArrayReplacesStoredArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [AppendingToken("default")])

        userDefaults.set(key, to: [AppendingToken("red")])
        userDefaults.set(key, to: [])

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [String], [])
        XCTAssertEqual(userDefaults.get(key), [])
    }

    func test_appending_set_failedElementLeavesStoredArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [AppendingToken]())
        let ubiquitousStore = MockUbiquitousKeyValueStore()

        for store in [userDefaults as any PersistentKeyValueStore, ubiquitousStore] {
            store.set(key, to: [AppendingToken("red")])
            store.set(key, to: [AppendingToken("blue"), AppendingToken("")])

            XCTAssertEqual(store.get(key), [AppendingToken("red")], "\(type(of: store))")
        }
    }

    func test_appending_nestedContainers_replaceStoredValues() {
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [[AppendingToken]]())
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: [AppendingToken]]())
        let optionalKey = PersistentKey("key:\(#function).optional", defaultValue: [AppendingToken?]())

        userDefaults.set(arrayKey, to: [[AppendingToken("red")]])
        userDefaults.set(arrayKey, to: [[AppendingToken("blue")], []])
        userDefaults.set(dictionaryKey, to: ["a": [AppendingToken("red")]])
        userDefaults.set(dictionaryKey, to: ["a": [AppendingToken("blue")], "b": []])
        userDefaults.set(optionalKey, to: [AppendingToken("red")])
        userDefaults.set(optionalKey, to: [nil, AppendingToken("blue"), nil])

        XCTAssertEqual(userDefaults.get(arrayKey), [[AppendingToken("blue")], []])
        XCTAssertEqual(userDefaults.get(dictionaryKey), ["a": [AppendingToken("blue")], "b": []])
        XCTAssertEqual(userDefaults.get(optionalKey), [AppendingToken("blue")])
    }

    func test_appending_nestedContainers_failedElementLeavesStoredValues() {
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [[AppendingToken]]())
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: [AppendingToken]]())
        let optionalKey = PersistentKey("key:\(#function).optional", defaultValue: [AppendingToken?]())

        userDefaults.set(arrayKey, to: [[AppendingToken("red")]])
        userDefaults.set(arrayKey, to: [[AppendingToken("blue")], [AppendingToken("")]])
        userDefaults.set(dictionaryKey, to: ["a": [AppendingToken("red")]])
        userDefaults.set(dictionaryKey, to: ["a": [AppendingToken("blue")], "b": [AppendingToken("")]])
        userDefaults.set(optionalKey, to: [AppendingToken("red")])
        userDefaults.set(optionalKey, to: [nil, AppendingToken("")])

        XCTAssertEqual(userDefaults.get(arrayKey), [[AppendingToken("red")]])
        XCTAssertEqual(userDefaults.get(dictionaryKey), ["a": [AppendingToken("red")]])
        XCTAssertEqual(userDefaults.get(optionalKey), [AppendingToken("red")])
    }

    func test_appending_checkedConversion() throws {
        let representation = [AppendingToken].persistentKeyValueRepresentation

        XCTAssertEqual(
            try representation.encode([AppendingToken("blue"), AppendingToken("green")], format: .userDefaults)
                as? [String],
            ["blue", "green"]
        )
        XCTAssertEqual(try representation.encode([], format: .userDefaults) as? [String], [])
        XCTAssertThrowsError(
            try representation.encode([AppendingToken("blue"), AppendingToken("")], format: .userDefaults)
        ) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .encodingFailed)
        }
    }

    func test_appending_register_storesArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [AppendingToken("blue")])

        defer {
            userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        }

        userDefaults.register(key)

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [String], ["blue"])
    }
}

// MARK: - Omitted Element Tests

extension CustomContainerHookTests {
    func test_set_arrayOfOnlyNilElements_storesEmptyArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [Int?]([1]))

        userDefaults.set(key, to: [2])
        userDefaults.set(key, to: [nil, nil])

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], [])
        XCTAssertEqual(userDefaults.get(key), [])
    }

    // A custom representation's container methods report a failed element by leaving it out, so checked conversion
    // cannot tell an element that encodes to `nil` from a failure without encoding it again, which is exponential in
    // the depth of a recursive value. It treats a missing result as a failure instead.

    func test_set_arrayOfOnlyRemovedCustomElements_leavesStoredArray() {
        let key = PersistentKey("key:\(#function)", defaultValue: [ConversionOnlyValue(1)])

        userDefaults.set(key, to: [ConversionOnlyValue(2)])
        userDefaults.set(key, to: [ConversionOnlyValue(0)])

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], [2])
    }

    func test_set_arrayWithSomeRemovedCustomElements_omitsThem() {
        let key = PersistentKey("key:\(#function)", defaultValue: [ConversionOnlyValue(1)])

        userDefaults.set(key, to: [ConversionOnlyValue(2), ConversionOnlyValue(0), ConversionOnlyValue(3)])

        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], [2, 3])
    }

    func test_set_dictionaryWithRemovedCustomValue_leavesStoredDictionary() {
        let key = PersistentKey("key:\(#function)", defaultValue: ["default": ConversionOnlyValue(1)])

        userDefaults.set(key, to: ["a": ConversionOnlyValue(2)])
        userDefaults.set(key, to: ["a": ConversionOnlyValue(0)])
        userDefaults.set(key, to: ["a": ConversionOnlyValue(3), "b": ConversionOnlyValue(0)])

        XCTAssertEqual(userDefaults.dictionary(forKey: key.id) as? [String: Int], ["a": 2])
    }

    func test_checkedEncode_arrayOfOnlyNilElements_returnsEmptyArray() throws {
        let representation = [ConversionOnlyValue?].persistentKeyValueRepresentation

        XCTAssertEqual(try representation.encode([nil, nil], format: .propertyList) as? [Int], [])
        XCTAssertEqual(try representation.encode([nil, .init(2), .init(0)], format: .propertyList) as? [Int], [2])
        XCTAssertThrowsError(try representation.encode([nil, .init(0)], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .encodingFailed)
        }
        XCTAssertThrowsError(try representation.encode([nil, .init(-1)], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .encodingFailed)
        }
    }

    func test_checkedEncode_failedCustomDictionaryValue_throwsEncodingFailed() {
        let representation = [String: ConversionOnlyValue].persistentKeyValueRepresentation

        XCTAssertThrowsError(try representation.encode(["a": .init(1), "b": .init(-1)], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }
        XCTAssertThrowsError(try representation.encode(["a": .init(1), "b": .init(0)], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed)
        }
    }
}

// MARK: - Hook Rejection Tests

extension CustomContainerHookTests {
    func test_checkedDecode_arrayHookRejection_throws() {
        let representation = [HookRejectedValue].persistentKeyValueRepresentation

        XCTAssertEqual(try representation.decode(storageObject: [1, 2], format: .propertyList), [.init(1), .init(2)])
        XCTAssertThrowsError(try representation.decode(storageObject: [1, -2], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }

    func test_checkedDecode_dictionaryHookRejection_throws() {
        let representation = [String: HookRejectedValue].persistentKeyValueRepresentation

        XCTAssertEqual(try representation.decode(storageObject: ["a": 1], format: .propertyList), ["a": .init(1)])
        XCTAssertThrowsError(try representation.decode(storageObject: ["a": 1, "b": -2], format: .propertyList)) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }

    func test_checkedDecode_elementFailurePreservesError() {
        let arrays = [ConversionOnlyValue].persistentKeyValueRepresentation
        let dictionaries = [String: ConversionOnlyValue].persistentKeyValueRepresentation

        XCTAssertThrowsError(try arrays.decode(storageObject: [1, "2"], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
        XCTAssertThrowsError(try dictionaries.decode(storageObject: ["a": "2"], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
    }

    func test_checkedEncode_dictionaryHookRejection_throws() {
        let representation = [String: HookRejectedValue].persistentKeyValueRepresentation

        XCTAssertEqual(try representation.encode(["a": .init(1)], format: .propertyList) as? [String: Int], ["a": 1])
        XCTAssertThrowsError(try representation.encode(["a": .init(-1)], format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .encodingFailed)
        }
    }
}

// MARK: - Hook Rejected Value Definition

/// A value whose container hooks reject negative numbers even though its scalar conversions accept them, so a test
/// can tell whether a conversion went through the container hooks.
private struct HookRejectedValue: Equatable, KeyValuePersistible {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    static var persistentKeyValueRepresentation: HookRejectedValueRepresentation {
        HookRejectedValueRepresentation()
    }
}

/// The representation of ``HookRejectedValue``.
private struct HookRejectedValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> HookRejectedValue {
        guard let number = storageObject as? Int else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return HookRejectedValue(number)
    }

    func encode(_ value: HookRejectedValue, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value.number
    }

    // MARK: Interfacing with Property List Array

    func get(from propertyListArray: [Any]) -> [HookRejectedValue]? {
        guard let numbers = propertyListArray as? [Int], numbers.allSatisfy({ $0 >= 0 }) else {
            return nil
        }

        return numbers.map(HookRejectedValue.init)
    }

    // MARK: Interfacing with Property List Dictionary

    func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> HookRejectedValue? {
        guard let number = propertyListDictionary[dictionaryKey] as? Int, number >= 0 else {
            return nil
        }

        return HookRejectedValue(number)
    }

    func set(_ dictionaryKey: String, to value: HookRejectedValue, in propertyListDictionary: inout [String: Any]) {
        guard value.number >= 0 else {
            return
        }

        propertyListDictionary[dictionaryKey] = value.number
    }
}
