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

    // MARK: Normalization Tests

    func test_set_compactionThatChangesValueType_storesValueUnchanged() {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"
        let value: any OptionalIntArrayMarker = [1, nil, 3] as [Int?]

        // Coercing to the existential keeps it from being opened, so the store sees the existential as `Value`.
        store.set(value as any OptionalIntArrayMarker, forKey: keyID)

        XCTAssertEqual(store.object(forKey: keyID) as? [Int?], [1, nil, 3])
    }

    func test_set_foundationArray_readsBackThroughKey() {
        let store = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")

        store.set(key, to: NSMutableArray(array: [1, 2, 3]))

        XCTAssertTrue(store.object(forKey: key.id) is NSMutableArray)
        XCTAssertEqual(store.get(key), NSMutableArray(array: [1, 2, 3]))
    }

    func test_set_foundationDictionary_storesValueUnchanged() {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"

        store.set(NSMutableDictionary(dictionary: ["a": 1]), forKey: keyID)

        XCTAssertEqual(store.object(forKey: keyID) as? NSMutableDictionary, NSMutableDictionary(dictionary: ["a": 1]))
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

    // MARK: Reentrancy Tests

    func test_copy_keyIdentifierCharactersReadStoreAndMigrate_doesNotDeadlock() {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let name = "key:\(#function).pr\u{E9}f\u{E9}rence"
        let identifier = AccessObservingString.make(name)
        let key = PersistentKey(identifier as String, defaultValue: 0)
        let unrelatedKey = PersistentKey("unrelated:\(#function)", defaultValue: 0)
        let didReadStore = LockedFlag(false)

        source.set(PersistentKey(name, defaultValue: 0), to: 7)
        source.set(unrelatedKey, to: 1)
        identifier.onAccess = {
            _ = source.object(forKey: "unrelated")
            _ = try? source.copy(unrelatedKey, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            didReadStore.value = true
        }

        guard assertCompletes({
            let report = try? source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            XCTAssertEqual(report?.outcomes.map(\.status), [.copied])
        }) else {
            return
        }

        identifier.onAccess = nil

        XCTAssertTrue(didReadStore.value)
        XCTAssertEqual(destination.get(PersistentKey(name, defaultValue: 0)), 7)
    }

    func test_deregister_releasedKeyIdentifierReadsStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let name = "key:\(#function).preference"
        let didReadStore = LockedFlag(false)
        let observer = RecordingKeyObserver()

        autoreleasepool {
            let keyID = releaseObservingKeyID(name) {
                _ = store.object(forKey: "unrelated")
                didReadStore.value = true
            }

            register(observer, for: PersistentKey(keyID, defaultValue: 0), in: store)
        }

        guard assertCompletes({
            store.deregister(observer, for: PersistentKey(name, defaultValue: 0), context: nil)
        }) else {
            return
        }

        store.set(1, forKey: name)

        XCTAssertTrue(didReadStore.value)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func test_get_keyIdentifierReadsStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let key = StoreReadingKey(store: store, suffix: #function)

        assertCompletes {
            store.set(key, to: 7)
            XCTAssertEqual(store.get(key), 7)
            store.remove(key)
            XCTAssertEqual(store.get(key), 0)
        }
    }

    func test_keyIdentifierCharactersReadStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let name = "key:\(#function).pr\u{E9}f\u{E9}rence"
        let identifier = AccessObservingString.make(name)
        let key = PersistentKey(identifier as String, defaultValue: 0)
        let didReadStore = LockedFlag(false)
        let observer = RecordingKeyObserver()

        store.set(PersistentKey(name, defaultValue: 0), to: 7)
        identifier.onAccess = {
            _ = store.object(forKey: "unrelated")
            didReadStore.value = true
        }

        guard assertCompletes({
            XCTAssertEqual(store.get(key), 7)
            store.register(
                observer: observer,
                for: key,
                with: nil,
                and: #selector(NSObject.observeValue(forKeyPath:of:change:context:))
            )
            store.set(key, to: 9)
            store.deregister(observer, for: key, context: nil)
            store.remove(key)
        }) else {
            return
        }

        identifier.onAccess = nil

        XCTAssertTrue(didReadStore.value)
        XCTAssertEqual(observer.observations.map(\.keyPath), [name])
        XCTAssertNil(store.object(forKey: name))
    }

    func test_move_releasedSourceKeyIdentifierReadsStore_doesNotDeadlock() {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let name = "key:\(#function).preference"
        let didReadStore = LockedFlag(false)

        autoreleasepool {
            let keyID = releaseObservingKeyID(name) {
                _ = source.object(forKey: "unrelated")
                didReadStore.value = true
            }

            source.set(PersistentKey(keyID, defaultValue: 0), to: 7)
        }

        guard assertCompletes({
            let key = PersistentKey(name, defaultValue: 0)
            let report = try? source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)
            XCTAssertEqual(report?.outcomes.map(\.status), [.moved])
        }) else {
            return
        }

        XCTAssertTrue(didReadStore.value)
        XCTAssertNil(source.object(forKey: name))
        XCTAssertEqual(destination.object(forKey: name) as? Int, 7)
    }

    func test_register_prunedKeyIdentifierReadsStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let name = "key:\(#function).preference"
        let didReadStore = LockedFlag(false)
        let observer = RecordingKeyObserver()

        autoreleasepool {
            let keyID = releaseObservingKeyID(name) {
                _ = store.object(forKey: "unrelated")
                didReadStore.value = true
            }

            register(RecordingKeyObserver(), for: PersistentKey(keyID, defaultValue: 0), in: store)
        }

        // The first observer has been deallocated, so registering prunes its registration and releases the identifier.
        guard assertCompletes({
            store.register(
                observer: observer,
                for: PersistentKey(name, defaultValue: 0),
                with: nil,
                and: #selector(NSObject.observeValue(forKeyPath:of:change:context:))
            )
        }) else {
            return
        }

        store.set(1, forKey: name)

        XCTAssertTrue(didReadStore.value)
        XCTAssertEqual(observer.observations.map(\.keyPath), [name])
    }

    func test_removeObject_releasedKeyIdentifierReadsStore_doesNotDeadlock() {
        // The store keeps an ASCII identifier backed by its `NSString` and copies a non-ASCII one.
        for name in ["key:\(#function).preference", "key:\(#function).pr\u{E9}f\u{E9}rence"] {
            let store = InMemoryPersistentKeyValueStore()
            let didReadStore = LockedFlag(false)

            autoreleasepool {
                let keyID = releaseObservingKeyID(name) {
                    _ = store.object(forKey: "unrelated")
                    didReadStore.value = true
                }

                store.set(PersistentKey(keyID, defaultValue: 0), to: 7)
            }

            guard assertCompletes({
                let key = PersistentKey(name, defaultValue: 0)
                XCTAssertEqual(store.get(key), 7)
                store.remove(key)
            }) else {
                return
            }

            XCTAssertTrue(didReadStore.value, name)
            XCTAssertNil(store.object(forKey: name), name)
        }
    }

    func test_removeObject_releasedValueReadsStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"
        let didReadStore = LockedFlag(false)

        store.set(StoreReadingObject(store: store, didReadStore: didReadStore), forKey: keyID)

        assertCompletes {
            store.removeObject(forKey: keyID)
        }

        XCTAssertTrue(didReadStore.value)
    }

    func test_set_replacedValueReadsStore_doesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"
        let didReadStore = LockedFlag(false)

        store.set(StoreReadingObject(store: store, didReadStore: didReadStore), forKey: keyID)

        assertCompletes {
            store.set(1, forKey: keyID)
            XCTAssertEqual(store.object(forKey: keyID) as? Int, 1)
        }

        XCTAssertTrue(didReadStore.value)
    }

    // MARK: Remove Object Tests

    func test_removeObject_notifiesObservers() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = RecordingKeyObserver()

        store.set("storedValue", forKey: key.id)
        register(observer, for: key, in: store)
        store.removeObject(forKey: key.id)

        XCTAssertEqual(observer.observations.map(\.keyPath), [key.id])
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
        let observer = RecordingKeyObserver()

        register(observer, for: key, in: store)
        store.set("storedValue", forKey: key.id)

        XCTAssertEqual(observer.observations.map(\.keyPath), [key.id])
        XCTAssertEqual(store.get(key), "storedValue")
    }
}

// MARK: - Private Helpers

private extension InMemoryPersistentKeyValueStoreAccessorTests {
    /// Runs `body` on another thread and fails, instead of hanging, if it does not finish, returning whether it
    /// finished.
    ///
    /// A deadlocked store stays locked, so callers must not access it after this returns `false`.
    @discardableResult
    func assertCompletes(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping @Sendable () -> Void
    ) -> Bool {
        let finished = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            body()
            finished.signal()
        }

        let result = finished.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success, "The store deadlocked.", file: file, line: line)

        return result == .success
    }

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

/// Marks only arrays of optional integers, so compacting such an array would produce a value that no longer conforms.
private protocol OptionalIntArrayMarker {
}

extension Array: OptionalIntArrayMarker where Element == Int? {
}

/// A key whose identifier reads another key from the same store.
private struct StoreReadingKey: PersistentKeyProtocol {
    let store: InMemoryPersistentKeyValueStore
    let suffix: String

    var defaultValue: Int {
        0
    }

    var id: String {
        "key:\(suffix).\(store.get(PersistentKey("prefix:\(suffix)", defaultValue: "value")))"
    }

    var representation: any PersistentKeyValueRepresentation<Int> {
        Int.persistentKeyValueRepresentation
    }

    func get(from userDefaults: UserDefaults) -> Int {
        representation.get(id, from: userDefaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Int {
        representation.get(id, from: ubiquitousStore) ?? defaultValue
    }

    func remove(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        ubiquitousStore.removeObject(forKey: id)
    }

    func set(to newValue: Int, in userDefaults: UserDefaults) {
        representation.set(id, to: newValue, in: userDefaults)
    }

    @available(watchOS 9.0, *)
    func set(to newValue: Int, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        representation.set(id, to: newValue, in: ubiquitousStore)
    }
}

/// A value whose `deinit` reads the store that held it.
private final class StoreReadingObject: Sendable {
    let didReadStore: LockedFlag
    let store: InMemoryPersistentKeyValueStore

    init(store: InMemoryPersistentKeyValueStore, didReadStore: LockedFlag) {
        self.didReadStore = didReadStore
        self.store = store
    }

    deinit {
        _ = store.object(forKey: "unrelated")
        didReadStore.value = true
    }
}
