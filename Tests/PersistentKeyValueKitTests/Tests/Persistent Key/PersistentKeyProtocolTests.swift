//
//  PersistentKeyProtocolTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyProtocolTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    
    // MARK: XCTestCase Implementation
    
    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyProtocolTests", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        userDefaults = nil
        suiteName = nil
    }
}

// MARK: - General Tests

extension PersistentKeyProtocolTests {
    // MARK: Tests
    
    func test_registerDefault() {
        let defaultValue: String = UUID().uuidString
        let key = PersistentKey(UUID().uuidString, defaultValue: defaultValue)
        
        var dictionary: [String: Any] = [:]
        
        type(of: defaultValue).persistentKeyValueRepresentation.set(key.id, to: defaultValue, in: &dictionary)
        
        key.registerDefault(in: &dictionary)
        
        XCTAssertEqual(dictionary[key.id] as? String, defaultValue)
    }

    func test_registerDefault_customFormat_usesUserDefaultsEncoding() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: FormatValue(5))
        var dictionary: [String: Any] = [:]

        key.registerDefault(in: &dictionary)
        userDefaults.register(key)

        XCTAssertEqual(dictionary[key.id] as? String, "defaults:5")
        XCTAssertEqual(key.representation.get(key.id, from: userDefaults), FormatValue(5))
    }

    func test_registerDefault_encodingFails_leavesDictionaryUnchanged() {
        let key = PersistentKey("key:\(#function)", defaultValue: FormatValue(-1))
        var dictionary: [String: Any] = [key.id: "stale"]

        key.registerDefault(in: &dictionary)

        XCTAssertEqual(dictionary[key.id] as? String, "stale")
    }

    func test_registerDefault_nilEncoding_removesEntry() {
        let key = PersistentKey<Int?>("key:\(#function)", defaultValue: nil)
        var dictionary: [String: Any] = [key.id: "stale"]

        key.registerDefault(in: &dictionary)

        XCTAssertNil(dictionary[key.id])
    }

    func test_registerDefault_nonPropertyListEncoding_leavesDictionaryUnchanged() {
        let key = PersistentKey("key:\(#function)", defaultValue: 0, representation: NonPropertyListRepresentation())
        var dictionary: [String: Any] = [key.id: "stale"]

        key.registerDefault(in: &dictionary)

        XCTAssertEqual(dictionary[key.id] as? String, "stale")
    }

    func test_registerDefault_webURL_readsBackWebURL() throws {
        let defaultValue = try XCTUnwrap(URL(string: "https://example.com/path?query=1#fragment"))
        let key = PersistentKey("key:\(#function)", defaultValue: defaultValue)

        userDefaults.register(key)

        XCTAssertEqual(userDefaults.url(forKey: key.id), defaultValue)
        XCTAssertEqual(key.representation.get(key.id, from: userDefaults), defaultValue)
    }
}

// MARK: - Private Types

/// A value whose representation stores a different string for each storage format and fails for negative values.
private struct FormatValue: Equatable, KeyValuePersistible {
    let raw: Int

    init(_ raw: Int) {
        self.raw = raw
    }

    static var persistentKeyValueRepresentation: FormatRepresentation {
        FormatRepresentation()
    }
}

private struct FormatRepresentation: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> FormatValue {
        guard
            let string = storageObject as? String,
            string.hasPrefix(prefix(for: format)),
            let raw = Int(string.dropFirst(prefix(for: format).count))
        else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return FormatValue(raw)
    }

    func encode(_ value: FormatValue, format: PersistentKeyValueStorageFormat) throws -> Any? {
        guard value.raw >= 0 else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return "\(prefix(for: format))\(value.raw)"
    }

    private func prefix(for format: PersistentKeyValueStorageFormat) -> String {
        format == .userDefaults ? "defaults:" : "plist:"
    }
}

/// A representation whose encoding is not a property list.
private struct NonPropertyListRepresentation: PersistentKeyValueRepresentation {
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Int {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }

    func encode(_ value: Int, format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSObject()
    }
}
