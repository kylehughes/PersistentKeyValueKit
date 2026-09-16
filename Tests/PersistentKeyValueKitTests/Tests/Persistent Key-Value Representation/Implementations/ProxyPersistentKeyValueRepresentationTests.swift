//
//  ProxyPersistentKeyValueRepresentationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class ProxyPersistentKeyValueRepresentationTests: XCTestCase {}

// MARK: Initialization Tests

extension ProxyPersistentKeyValueRepresentationTests {
    // MARK: Tests
    
    @MainActor
    func test_init() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { String($0) },
            from: { Int($0) ?? 0 }
        )
        
        XCTAssertEqual(representation.to(42), "42")
        XCTAssertEqual(representation.from("42"), 42)
        XCTAssertEqual(representation.from("invalid"), 0)
    }
    
    @MainActor
    func test_init_otherRepresentation() {
        // October 4, 2021, 00:00:00 UTC
        let timeInterval: TimeInterval = 1633305600
        let date = Date(timeIntervalSince1970: timeInterval)
        
        let representation = ProxyPersistentKeyValueRepresentation<Date, String>(
            other: ProxyPersistentKeyValueRepresentation(
                to: { String($0) },
                from: { TimeInterval($0) ?? 0 }
            ),
            to: \.timeIntervalSince1970,
            from: Date.init(timeIntervalSince1970:)
        )
        
        XCTAssertEqual(representation.from("invalid"), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(representation.to(date), "1633305600.0")
        XCTAssertEqual(
            representation.from("1633305600.0")?.timeIntervalSince1970 ?? 0,
            date.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    @MainActor
    func test_init_otherRepresentation_returnsNilWhenInnerRepresentationCannotDeserialize() {
        let inner = ProxyPersistentKeyValueRepresentation<TimeInterval, String>(
            to: {
                String($0)
            },
            from: { _ in
                nil
            }
        )
        let representation = ProxyPersistentKeyValueRepresentation<Date, String>(
            other: inner,
            to: {
                $0.timeIntervalSince1970
            },
            from: Date.init(timeIntervalSince1970:)
        )

        XCTAssertNil(representation.from("not-a-date"))
    }
    
    @MainActor
    func test_init_optional_to() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { $0 > 0 ? String($0) : nil },
            from: { Int($0) ?? 0 }
        )
        
        XCTAssertEqual(representation.to(42), "42")
        XCTAssertNil(representation.to(-5))
        XCTAssertEqual(representation.from("42"), 42)
        XCTAssertEqual(representation.from("invalid"), 0)
    }
    
    @MainActor
    func test_init_optional_from() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { String($0) },
            from: { Int($0) }
        )
        
        XCTAssertEqual(representation.to(42), "42")
        XCTAssertEqual(representation.from("42"), 42)
        XCTAssertNil(representation.from("invalid"))
    }
    
    @MainActor
    func test_init_optional_both() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { $0 > 0 ? String($0) : nil },
            from: { Int($0) }
        )
        
        XCTAssertEqual(representation.to(42), "42")
        XCTAssertNil(representation.to(-5))
        XCTAssertEqual(representation.from("42"), 42)
        XCTAssertNil(representation.from("invalid"))
    }

    @MainActor
    func test_protocol_failedSerializationLeavesPropertyListArrayUnchanged() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { _ in
                nil
            },
            from: {
                Int($0)
            }
        )
        var propertyListArray: [Any] = ["existing"]

        representation.set([1], to: &propertyListArray)

        XCTAssertEqual(propertyListArray as? [String], ["existing"])
    }

    @MainActor
    func test_protocol_failedSerializationLeavesPropertyListDictionaryUnchanged() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { _ in
                nil
            },
            from: {
                Int($0)
            }
        )
        var propertyListDictionary: [String: Any] = ["key": "existing"]

        representation.set("key", to: 1, in: &propertyListDictionary)

        XCTAssertEqual(propertyListDictionary["key"] as? String, "existing")
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_protocol_failedSerializationLeavesUbiquitousStoreUnchanged() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { _ in
                nil
            },
            from: {
                Int($0)
            }
        )
        let key = "key:\(#function)"
        let ubiquitousStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore.mockDefault
        ubiquitousStore.set("existing", forKey: key)

        defer {
            ubiquitousStore.removeObject(forKey: key)
        }

        representation.set(key, to: 1, in: ubiquitousStore)

        XCTAssertEqual(ubiquitousStore.object(forKey: key) as? String, "existing")
    }

    @MainActor
    func test_protocol_failedSerializationLeavesUserDefaultsUnchanged() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: { _ in
                nil
            },
            from: {
                Int($0)
            }
        )
        let suiteName = "PersistentKeyValueKit.ProxyRepresentation.\(UUID().uuidString)"
        let key = "key:\(#function)"
        let userDefaults = UserDefaults(suiteName: suiteName)!

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set("existing", forKey: key)

        representation.set(key, to: 1, in: userDefaults)

        XCTAssertEqual(userDefaults.string(forKey: key), "existing")
    }

    @MainActor
    func test_protocol_getArrayReturnsNilWhenProxyCannotDeserialize() {
        let representation = ProxyPersistentKeyValueRepresentation<Int, String>(
            to: {
                String($0)
            },
            from: {
                Int($0)
            }
        )

        XCTAssertNil(representation.get(from: ["1", "invalid"]))
    }
}
