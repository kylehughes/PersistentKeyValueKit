//
//  InMemoryPersistentKeyValueStoreAccessorTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
@testable import PersistentKeyValueKit
import XCTest

final class InMemoryPersistentKeyValueStoreAccessorTests: XCTestCase {
    // MARK: Object Tests

    func test_object_absentKey() {
        let store = InMemoryPersistentKeyValueStore()

        XCTAssertNil(store.object(forKey: "key:\(#function)"))
    }

    func test_object_explicitNil() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int?>("key:\(#function)", defaultValue: 5)

        store.set(key, to: nil)

        let object = try XCTUnwrap(store.object(forKey: key.id))
        XCTAssertEqual(object as? Int?, .some(nil))
        XCTAssertNil(store.get(key))
    }

    func test_object_storedValue() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)

        store.set(key, to: 7)

        XCTAssertEqual(store.object(forKey: key.id) as? Int, 7)
    }

    // MARK: Optional Default Tests

    func test_get_absentOptionalKeyReturnsNonNilDefault() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int?>("key:\(#function)", defaultValue: 5)

        XCTAssertEqual(store.get(key), 5)
    }

    func test_get_removedOptionalKeyReturnsNonNilDefault() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int?>("key:\(#function)", defaultValue: 5)

        store.set(key, to: nil)
        store.remove(key)

        XCTAssertNil(store.object(forKey: key.id))
        XCTAssertEqual(store.get(key), 5)
    }

    // MARK: Remove Object Tests

    func test_removeObject_notifiesObservers() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = AccessorObservationRecorder()

        store.set("storedValue", forKey: key.id)
        register(observer, for: key, in: store)
        store.removeObject(forKey: key.id)

        XCTAssertEqual(observer.keyPaths, [key.id])
        XCTAssertEqual(store.get(key), "defaultValue")
    }

    func test_removeObject_removesMigrationSnapshot() throws {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"

        store.set("storedValue", forKey: keyID)
        store.removeObject(forKey: keyID)

        XCTAssertNil(try store.migrationSnapshot(for: keyID))
    }

    // MARK: Set Tests

    func test_set_advancesMigrationRevision() throws {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"

        store.set("first", forKey: keyID)
        let first = try XCTUnwrap(store.migrationSnapshot(for: keyID))
        store.set("second", forKey: keyID)
        let second = try XCTUnwrap(store.migrationSnapshot(for: keyID))

        XCTAssertGreaterThan(second.revision, first.revision)
        XCTAssertFalse(try store.migrationSnapshotIsCurrent(first, for: keyID))
        XCTAssertTrue(try store.migrationSnapshotIsCurrent(second, for: keyID))
    }

    func test_set_normalizesOptionalArray() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[Int?]>("key:\(#function)", defaultValue: [])

        store.set([1, nil, 3] as [Int?], forKey: key.id)

        XCTAssertEqual(store.object(forKey: key.id) as? [Int], [1, 3])
        XCTAssertEqual(store.get(key), [1, 3])
    }

    func test_set_normalizesOptionalDictionary() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[String: Int?]>("key:\(#function)", defaultValue: [:])

        store.set(["a": 1, "b": nil] as [String: Int?], forKey: key.id)

        XCTAssertEqual(store.object(forKey: key.id) as? [String: Int], ["a": 1])
        XCTAssertEqual(store.get(key), ["a": 1])
    }

    func test_set_notifiesObservers() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = AccessorObservationRecorder()

        register(observer, for: key, in: store)
        store.set("storedValue", forKey: key.id)

        XCTAssertEqual(observer.keyPaths, [key.id])
        XCTAssertEqual(store.get(key), "storedValue")
    }
}

// MARK: - Private Helpers

private extension InMemoryPersistentKeyValueStoreAccessorTests {
    func register<Key>(
        _ observer: NSObject,
        for key: Key,
        in store: InMemoryPersistentKeyValueStore
    ) where Key: PersistentKeyProtocol {
        store.register(
            observer: observer,
            for: key,
            with: nil,
            and: #selector(NSObject.observeValue(forKeyPath:of:change:context:))
        )
    }
}

private final class AccessorObservationRecorder: NSObject {
    private(set) var keyPaths: [String?]

    override init() {
        keyPaths = []

        super.init()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        keyPaths.append(keyPath)
    }
}
