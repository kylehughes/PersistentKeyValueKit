//
//  StorablePropertyListTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Covers encodings that binary property-list validation accepts but Foundation stores reject, such as a keyed
/// archive's property list, which contains UIDs. `UserDefaults` removes the previous value before rejecting one.
final class StorablePropertyListTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.StorablePropertyList", function: name)
        userDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }
}

// MARK: - Validation Tests

extension StorablePropertyListTests {
    func test_isStorablePropertyList_acceptsStoreTypes() throws {
        let objects: [Any] = [
            "text",
            42,
            1.5,
            true,
            kCFBooleanFalse as Any,
            NSDecimalNumber(string: "1.25"),
            Date(),
            Data([1, 2]),
            try archivedPropertyListData(),
            [1, "two", [3.0]] as [Any],
            ["a": ["b": Data([4])], "c": [Date()]] as [String: Any],
            NSMutableArray(array: [NSMutableDictionary(dictionary: ["d": "e"])]),
        ]

        for object in objects {
            XCTAssertTrue(isStorablePropertyList(object), "\(object)")
        }
    }

    func test_isStorablePropertyList_rejectsArchiveUIDsAtAnyDepth() throws {
        let archive = try archivedPropertyList()
        let uid = try archiveUID()

        XCTAssertTrue(PropertyListSerialization.propertyList(archive, isValidFor: .binary))
        XCTAssertFalse(isStorablePropertyList(archive))
        XCTAssertFalse(isStorablePropertyList(uid))
        XCTAssertFalse(isStorablePropertyList([1, uid] as [Any]))
        XCTAssertFalse(isStorablePropertyList(["field": uid] as [String: Any]))
        XCTAssertFalse(isStorablePropertyList([["field": [uid]]] as [Any]))
    }

    func test_isStorablePropertyList_rejectsObjectsThatAreNotPropertyLists() {
        let looped = NSMutableArray()
        looped.add(looped)

        XCTAssertFalse(isStorablePropertyList(NSNull()))
        XCTAssertFalse(isStorablePropertyList(URL(string: "https://example.com")!))
        XCTAssertFalse(isStorablePropertyList([1: "one"] as NSDictionary))
        XCTAssertFalse(isStorablePropertyList(looped))
    }
}

// MARK: - Ordinary Write Tests

extension StorablePropertyListTests {
    func test_userDefaultsWrite_ofArchivePropertyList_leavesPreviousValue() {
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedText("fallback"))

        userDefaults.set("previous", forKey: key.id)
        userDefaults.set(key, to: ArchivedText("candidate"))

        XCTAssertEqual(userDefaults.string(forKey: key.id), "previous")
    }

    func test_userDefaultsWrite_ofArchiveData_stores() {
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: ArchivedText("fallback"),
            representation: ArchivedTextRepresentation(storesData: true)
        )

        userDefaults.set("previous", forKey: key.id)
        userDefaults.set(key, to: ArchivedText("candidate"))

        XCTAssertTrue(userDefaults.object(forKey: key.id) is Data)
        XCTAssertEqual(userDefaults.get(key), ArchivedText("candidate"))
    }

    func test_userDefaultsWrite_ofPrimitiveArchivePropertyList_leavesPreviousValue() {
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedPrimitive("fallback"))

        userDefaults.set("previous", forKey: key.id)
        userDefaults.set(key, to: ArchivedPrimitive("candidate"))

        XCTAssertEqual(userDefaults.string(forKey: key.id), "previous")
    }

    func test_userDefaultsContainerWrites_ofArchivePropertyLists_leavePreviousValues() {
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [ArchivedText]())
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: ArchivedText]())

        userDefaults.set(["previous"], forKey: arrayKey.id)
        userDefaults.set(["entry": "previous"], forKey: dictionaryKey.id)
        userDefaults.set(arrayKey, to: [ArchivedText("candidate")])
        userDefaults.set(dictionaryKey, to: ["entry": ArchivedText("candidate")])

        XCTAssertEqual(userDefaults.stringArray(forKey: arrayKey.id), ["previous"])
        XCTAssertEqual(userDefaults.dictionary(forKey: dictionaryKey.id) as? [String: String], ["entry": "previous"])
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousStoreWrite_ofArchivePropertyList_leavesPreviousValue() {
        let store = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedText("fallback"))
        let dataKey = PersistentKey(
            "key:\(#function).data",
            defaultValue: ArchivedText("fallback"),
            representation: ArchivedTextRepresentation(storesData: true)
        )

        store.set("previous", forKey: key.id)
        store.set(key, to: ArchivedText("candidate"))
        store.set(dataKey, to: ArchivedText("candidate"))

        XCTAssertEqual(store.string(forKey: key.id), "previous")
        XCTAssertEqual(store.get(dataKey), ArchivedText("candidate"))
    }

    func test_registration_ofArchivePropertyListDefault_registersNothing() {
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedText("default"))

        userDefaults.register(key)

        XCTAssertNil(userDefaults.object(forKey: key.id))
    }
}

// MARK: - Migration Tests

extension StorablePropertyListTests {
    func test_migrationToUserDefaults_ofArchivePropertyList_failsAtPrepare() throws {
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedText("fallback"))

        source.set(key, to: ArchivedText("candidate"))
        userDefaults.set("previous", forKey: key.id)

        let report = try source.move(
            key,
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyValueConversionError, .encodingFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(key), ArchivedText("candidate"))
        XCTAssertEqual(userDefaults.string(forKey: key.id), "previous")
    }

    func test_migrationToUserDefaults_ofArchiveData_moves() throws {
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: ArchivedText("fallback"),
            representation: ArchivedTextRepresentation(storesData: true)
        )

        source.set(key, to: ArchivedText("candidate"))

        let report = try source.move(
            key,
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(userDefaults.get(key), ArchivedText("candidate"))
    }

    @available(watchOS 9.0, *)
    func test_migrationToUbiquitousStore_ofArchivePropertyList_failsAtPrepare() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = StrictMigrationUbiquitousStore()
        let key = PersistentKey("key:\(#function)", defaultValue: ArchivedText("fallback"))

        source.set(key, to: ArchivedText("candidate"))
        destination.set("previous", forKey: key.id)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyValueConversionError, .encodingFailed)
        XCTAssertEqual(destination.string(forKey: key.id), "previous")
    }
}

// MARK: - Private Interface

private func archivedPropertyListData() throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: "archived" as NSString, requiringSecureCoding: true)
}

private func archivedPropertyList() throws -> NSDictionary {
    let data = try archivedPropertyListData()
    return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
}

private func archiveUID() throws -> Any {
    let top = try XCTUnwrap(archivedPropertyList()["$top"] as? NSDictionary)
    return try XCTUnwrap(top["root"])
}

// MARK: - Archived Text Definition

/// A string stored as a keyed archive, either as the archive's property list or as its `Data`.
private struct ArchivedText: Equatable, KeyValuePersistible {
    let text: String

    // MARK: Initialization

    init(_ text: String) {
        self.text = text
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: ArchivedTextRepresentation {
        ArchivedTextRepresentation(storesData: false)
    }
}

private struct ArchivedTextRepresentation: PersistentKeyValueRepresentation {
    /// Whether the archive is stored as `Data` rather than as its property list.
    let storesData: Bool

    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> ArchivedText {
        ArchivedText(try unarchivedText(from: storageObject))
    }

    func encode(_ value: ArchivedText, format: PersistentKeyValueStorageFormat) throws -> Any? {
        try archivedObject(for: value.text, storesData: storesData)
    }
}

// MARK: - Archived Primitive Definition

/// A string stored as a keyed archive's property list through the `PrimitiveKeyValuePersistible` default methods.
private struct ArchivedPrimitive: Equatable, PrimitiveKeyValuePersistible {
    let text: String

    // MARK: Initialization

    init(_ text: String) {
        self.text = text
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: PrimitivePersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    // MARK: PrimitiveKeyValuePersistible Implementation

    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        Self(try unarchivedText(from: storageObject))
    }

    func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        try archivedObject(for: text, storesData: false)
    }
}

private func archivedObject(for text: String, storesData: Bool) throws -> Any {
    let data = try NSKeyedArchiver.archivedData(withRootObject: text as NSString, requiringSecureCoding: true)
    return storesData ? data : try PropertyListSerialization.propertyList(from: data, format: nil)
}

private func unarchivedText(from storageObject: Any) throws -> String {
    let data = try storageObject as? Data
        ?? PropertyListSerialization.data(fromPropertyList: storageObject, format: .binary, options: 0)
    guard let text = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) else {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }

    return text as String
}
