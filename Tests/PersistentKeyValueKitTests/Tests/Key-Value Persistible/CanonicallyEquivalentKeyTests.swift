//
//  CanonicallyEquivalentKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that identifiers that are canonically equivalent but spelled differently, such as composed and decomposed
/// "café", stay distinct where Foundation keeps them distinct.
///
/// Foundation compares keys by their literal contents, while Swift's `String` treats canonically equivalent spellings
/// as equal. Registration and launch-argument lookup keep the literal identity. A Swift dictionary cannot hold both
/// spellings, so checked decoding of a stored dictionary fails rather than silently merge them.
final class CanonicallyEquivalentKeyTests: XCTestCase {
    private let composed = "caf\u{E9}"
    private let decomposed = "cafe\u{301}"

    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.CanonicallyEquivalentKey", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    /// Returns a Foundation dictionary that holds both spellings of "café" as separate keys.
    private func nativeDictionary(composedValue: Any, decomposedValue: Any) -> NSDictionary {
        let dictionary = NSMutableDictionary()

        dictionary[composed as NSString] = composedValue
        dictionary[decomposed as NSString] = decomposedValue

        return dictionary
    }
}

// MARK: - Registration Tests

extension CanonicallyEquivalentKeyTests {
    func test_register_keepsEquivalentIdentifiersSeparate() {
        let composedKey = PersistentKey("key:\(#function).\(composed)", defaultValue: 12)
        let decomposedKey = PersistentKey("key:\(#function).\(decomposed)", defaultValue: 29)

        XCTAssertEqual(composedKey.id, decomposedKey.id, "The identifiers must be canonically equivalent.")

        userDefaults.register(composedKey, decomposedKey)

        XCTAssertEqual(userDefaults.object(forKey: composedKey.id) as? Int, 12)
        XCTAssertEqual(userDefaults.object(forKey: decomposedKey.id) as? Int, 29)
        XCTAssertEqual(userDefaults.get(composedKey), 12)
        XCTAssertEqual(userDefaults.get(decomposedKey), 29)
    }

    func test_register_laterLiteralDuplicateWins() {
        let first = PersistentKey("key:\(#function)", defaultValue: 1)
        let second = PersistentKey("key:\(#function)", defaultValue: 2)

        userDefaults.register(first, second)

        XCTAssertEqual(userDefaults.object(forKey: first.id) as? Int, 2)
    }

    func test_register_laterRemovalDropsEarlierLiteralDuplicate() {
        let first = PersistentKey<Int?>("key:\(#function)", defaultValue: 1)
        let second = PersistentKey<Int?>("key:\(#function)", defaultValue: nil)

        userDefaults.register(first, second)

        XCTAssertNil(userDefaults.object(forKey: first.id))
    }

    func test_register_skipsKeyWhoseDefaultFailsToEncode() {
        let failing = PersistentKey("key:\(#function).failing", defaultValue: ConversionOnlyValue(-1))
        let succeeding = PersistentKey("key:\(#function).succeeding", defaultValue: ConversionOnlyValue(3))

        userDefaults.register(failing, succeeding)

        XCTAssertNil(userDefaults.object(forKey: failing.id))
        XCTAssertEqual(userDefaults.object(forKey: succeeding.id) as? Int, 3)
    }
}

// MARK: - Launch Argument Tests

extension CanonicallyEquivalentKeyTests {
    func test_get_launchArgumentForEquivalentIdentifierDoesNotCoercePersistedString() {
        let composedKey = PersistentKey("key:\(#function).\(composed)", defaultValue: -1)
        let decomposedKey = PersistentKey("key:\(#function).\(decomposed)", defaultValue: -1)

        userDefaults.setVolatileDomain([composedKey.id: "7"], forName: UserDefaults.argumentDomain)
        userDefaults.set("7", forKey: decomposedKey.id)

        XCTAssertEqual(userDefaults.get(composedKey), 7)
        XCTAssertEqual(userDefaults.get(decomposedKey), -1)
    }
}

// MARK: - Checked Dictionary Decoding Tests

extension CanonicallyEquivalentKeyTests {
    func test_decode_dictionaryWithEquivalentKeys_throws() {
        let representation = [String: Int].persistentKeyValueRepresentation
        let object = nativeDictionary(composedValue: 5, decomposedValue: 7)

        for format in [PersistentKeyValueStorageFormat.propertyList, .userDefaults, .ubiquitousKeyValueStore] {
            XCTAssertThrowsError(try representation.decode(storageObject: object, format: format)) { error in
                XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
            }
        }
    }

    func test_decode_nestedDictionaryWithEquivalentKeys_throws() {
        let inner = nativeDictionary(composedValue: 5, decomposedValue: 7)
        let dictionaryOfDictionaries = [String: [String: Int]].persistentKeyValueRepresentation
        let arrayOfDictionaries = [[String: Int]].persistentKeyValueRepresentation
        let optionalDictionaries = [[String: Int]?].persistentKeyValueRepresentation
        let proxies = [IntegerTable].persistentKeyValueRepresentation

        let outer = NSDictionary(object: inner, forKey: "outer" as NSString)
        let array = NSArray(object: inner)

        XCTAssertThrowsError(try dictionaryOfDictionaries.decode(storageObject: outer, format: .userDefaults))
        XCTAssertThrowsError(try arrayOfDictionaries.decode(storageObject: array, format: .userDefaults))
        XCTAssertThrowsError(try optionalDictionaries.decode(storageObject: array, format: .userDefaults))
        XCTAssertThrowsError(try proxies.decode(storageObject: array, format: .userDefaults))
    }

    func test_decode_dictionaryWithDistinctKeys_succeeds() throws {
        let representation = [String: [String: Int]].persistentKeyValueRepresentation
        let entries = ["a": 1, "b": 2]
        let inner = NSDictionary(dictionary: entries)
        let object = NSDictionary(object: inner, forKey: composed as NSString)

        let arrayOfDictionaries = [[String: Int]].persistentKeyValueRepresentation

        XCTAssertEqual(try representation.decode(storageObject: object, format: .userDefaults), [composed: entries])
        XCTAssertEqual(try arrayOfDictionaries.decode(storageObject: [inner], format: .userDefaults), [entries])
    }

    func test_decode_arrayOfDictionariesWithUndecodableEntry_throws() {
        let arrayOfDictionaries = [[String: Int]].persistentKeyValueRepresentation
        let proxies = [IntegerTable].persistentKeyValueRepresentation
        let stored: [Any] = [["a": 1, "b": "not a number"]]

        XCTAssertEqual([String: Int].persistentKeyValueRepresentation.get(from: stored), [["a": 1]])
        XCTAssertThrowsError(try arrayOfDictionaries.decode(storageObject: stored, format: .propertyList)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .invalidStorageValue)
        }
        XCTAssertThrowsError(try proxies.decode(storageObject: stored, format: .propertyList))
    }

    func test_get_dictionaryWithEquivalentKeys_keepsOneEntry() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [String: Int]())

        userDefaults.set(nativeDictionary(composedValue: 5, decomposedValue: 7), forKey: key.id)

        let value = userDefaults.get(key)

        XCTAssertEqual(value.count, 1)
        XCTAssertTrue([5, 7].contains(try XCTUnwrap(value[composed])))
    }

    func test_move_dictionaryWithEquivalentKeys_failsAtDecodeAndKeepsSource() throws {
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: [String: Int]())

        source.set(nativeDictionary(composedValue: 5, decomposedValue: 7), forKey: key.id)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)])
        XCTAssertEqual((source.object(forKey: key.id) as? NSDictionary)?.count, 2)
        XCTAssertNil(destination.object(forKey: key.id))
    }
}

// MARK: - Integer Table Definition

/// A value persisted through a proxy dictionary, so arrays of it reach dictionary conversion through the proxy.
private struct IntegerTable: Equatable, KeyValuePersistible {
    let entries: [String: Int]

    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(to: \.entries, from: IntegerTable.init(entries:))
    }
}
