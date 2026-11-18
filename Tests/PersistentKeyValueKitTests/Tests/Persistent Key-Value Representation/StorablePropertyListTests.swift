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

// MARK: - Custom Container Method Tests

extension StorablePropertyListTests {
    func test_userDefaultsCollectionWrites_ofCustomArchivePropertyLists_leavePreviousValues() {
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).array",
            writing: { [$0] },
            previous: ["previous"]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).dictionary",
            writing: { ["entry": $0] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).nestedArray",
            writing: { [[$0]] },
            previous: [["previous"]]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).arrayOfDictionaries",
            writing: { [["entry": $0]] },
            previous: [["entry": "previous"]]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).dictionaryOfArrays",
            writing: { ["entry": [$0]] },
            previous: ["entry": ["previous"]]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).optionalArray",
            writing: { [Optional($0)] },
            previous: ["previous"]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).optionalDictionary",
            writing: { ["entry": Optional($0)] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).doubleOptionalDictionary",
            writing: { ["entry": Optional(Optional($0))] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsWritesKeepPreviousValue(
            "key:\(#function).proxyDictionary",
            writing: { ["entry": ProxiedArchivedText(base: $0)] },
            previous: ["entry": "previous"]
        )
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousStoreCollectionWrites_ofCustomArchivePropertyLists_leavePreviousValues() {
        let store = MockUbiquitousKeyValueStore()
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [HookArchivedText]())
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: HookArchivedText]())
        let candidate = HookArchivedText("candidate", storesData: false)
        let control = HookArchivedText("control", storesData: true)

        store.set(["previous"], forKey: arrayKey.id)
        store.set(["entry": "previous"], forKey: dictionaryKey.id)
        store.set(arrayKey, to: [candidate])
        store.set(dictionaryKey, to: ["entry": candidate])

        XCTAssertEqual(store.array(forKey: arrayKey.id) as? [String], ["previous"])
        XCTAssertEqual(store.dictionary(forKey: dictionaryKey.id) as? [String: String], ["entry": "previous"])

        store.set(arrayKey, to: [control])
        store.set(dictionaryKey, to: ["entry": control])

        XCTAssertEqual(store.get(arrayKey), [control])
        XCTAssertEqual(store.get(dictionaryKey), ["entry": control])
    }

    func test_propertyListContainerWrites_ofCustomArchivePropertyLists_leaveContainersUnchanged() {
        let candidate = HookArchivedText("candidate", storesData: false)
        let control = HookArchivedText("control", storesData: true)
        let representation = [HookArchivedText].persistentKeyValueRepresentation
        var dictionary: [String: Any] = ["entry": "previous"]
        var array: [Any] = ["previous"]

        representation.set("entry", to: [candidate], in: &dictionary)
        representation.set([[candidate]], to: &array)

        XCTAssertEqual(dictionary as? [String: String], ["entry": "previous"])
        XCTAssertEqual(array as? [String], ["previous"])

        representation.set("entry", to: [control], in: &dictionary)
        representation.set([[control]], to: &array)

        XCTAssertEqual(representation.get("entry", from: dictionary), [control])
        XCTAssertEqual(representation.get(from: array), [[control]])
    }
}

// MARK: - Archive UID Comparison Tests

extension StorablePropertyListTests {
    func test_equal_comparesArchiveUIDsByValue() throws {
        let uids = try arrayArchiveUIDs()

        XCTAssertTrue(PropertyListMigrationStorage.equal(try archiveUID(), try archiveUID()))
        XCTAssertTrue(PropertyListMigrationStorage.equal(try archivedPropertyList(), try archivedPropertyList()))
        XCTAssertFalse(PropertyListMigrationStorage.equal(uids[0], uids[1]))
        XCTAssertFalse(PropertyListMigrationStorage.equal(uids[0], nil))
        XCTAssertFalse(PropertyListMigrationStorage.equal(nil, uids[0]))
        XCTAssertFalse(PropertyListMigrationStorage.equal(uids[0], 2))
        XCTAssertFalse(PropertyListMigrationStorage.equal(NSNull(), NSNull()))
    }

    func test_inMemorySnapshot_ofArchivePropertyList_detectsChangedUID() throws {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"
        let top = try XCTUnwrap(archivedPropertyList()["$top"] as? NSDictionary).mutableCopy() as! NSMutableDictionary
        let archive = try archivedPropertyList().mutableCopy() as! NSMutableDictionary

        archive["$top"] = top
        store.set(archive, forKey: keyID)

        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: keyID))

        XCTAssertTrue(try store.migrationSnapshotIsCurrent(snapshot, for: keyID))

        top["root"] = try arrayArchiveUIDs()[1]

        XCTAssertFalse(try store.migrationSnapshotIsCurrent(snapshot, for: keyID))
    }

    func test_inMemoryMove_ofArchivePropertyList_moves() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = ArchiveDictionaryKey("key:\(#function)")
        let archive = try archivedPropertyList()

        source.set(key, to: archive)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertTrue(PropertyListMigrationStorage.equal(destination.get(key), archive))
        XCTAssertNil(source.object(forKey: key.id))
    }

    func test_inMemoryCopy_ofArchivePropertyList_copies() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = ArchiveDictionaryKey("key:\(#function)")
        let archive = try archivedPropertyList()

        source.set(key, to: archive)

        let report = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.copied])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertTrue(PropertyListMigrationStorage.equal(destination.get(key), archive))
        XCTAssertTrue(PropertyListMigrationStorage.equal(source.get(key), archive))
    }
}

// MARK: - Assertions

extension StorablePropertyListTests {
    /// Asserts that a write of an archive property list that a custom container method produces leaves the previous
    /// value, and that a write of the archive as `Data` stores it.
    private func assertUserDefaultsWritesKeepPreviousValue<Value: Equatable & KeyValuePersistible & Sendable>(
        _ id: String,
        writing value: (HookArchivedText) -> Value,
        previous: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let control = value(HookArchivedText("control", storesData: true))
        let key = PersistentKey(id, defaultValue: control)

        userDefaults.set(previous, forKey: key.id)
        userDefaults.set(key, to: value(HookArchivedText("candidate", storesData: false)))

        XCTAssertEqual(userDefaults.object(forKey: key.id) as? NSObject, previous as? NSObject, file: file, line: line)

        userDefaults.removeObject(forKey: key.id)
        userDefaults.set(key, to: control)

        XCTAssertNotNil(userDefaults.object(forKey: key.id), file: file, line: line)
        XCTAssertEqual(userDefaults.get(key), control, file: file, line: line)
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

/// Returns the UIDs that refer to the elements of an archived two-element array, whose values differ.
private func arrayArchiveUIDs() throws -> [Any] {
    let data = try NSKeyedArchiver.archivedData(withRootObject: ["x", "y"] as NSArray, requiringSecureCoding: true)
    let archive = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
    let objects = try XCTUnwrap(archive["$objects"] as? NSArray)
    let array = try XCTUnwrap(objects[1] as? NSDictionary)
    return try XCTUnwrap(array["NS.objects"] as? [Any])
}

// MARK: - Archive Dictionary Key Definition

/// A key whose value is a keyed archive's property list, stored as the dictionary itself.
///
/// `NSDictionary` is not `Sendable`, so this key cannot be a `PersistentKey`.
private struct ArchiveDictionaryKey: PersistentKeyProtocol {
    let id: String

    // MARK: Initialization

    init(_ id: String) {
        self.id = id
    }

    // MARK: PersistentKeyProtocol Implementation

    var defaultValue: NSDictionary {
        NSDictionary()
    }

    var representation: any PersistentKeyValueRepresentation<NSDictionary> {
        ArchiveDictionaryRepresentation()
    }

    func get(from defaults: UserDefaults) -> NSDictionary {
        representation.get(id, from: defaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> NSDictionary {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSDictionary, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    @available(watchOS 9.0, *)
    func set(to value: NSDictionary, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
    }
}

private struct ArchiveDictionaryRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> NSDictionary {
        try XCTUnwrap(storageObject as? NSDictionary)
    }

    func encode(_ value: NSDictionary, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value
    }
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

// MARK: - Hook Archived Text Definition

/// A string stored as a keyed archive, either as the archive's property list or as its `Data`, whose representation
/// writes collections with its own container methods instead of the protocol's default implementations.
private struct HookArchivedText: Equatable, KeyValuePersistible {
    let text: String
    let storesData: Bool

    // MARK: Initialization

    init(_ text: String, storesData: Bool) {
        self.text = text
        self.storesData = storesData
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: HookArchivedTextRepresentation {
        HookArchivedTextRepresentation()
    }
}

private struct HookArchivedTextRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> HookArchivedText {
        HookArchivedText(try unarchivedText(from: storageObject), storesData: storageObject is Data)
    }

    func encode(_ value: HookArchivedText, format: PersistentKeyValueStorageFormat) throws -> Any? {
        try archivedObject(for: value.text, storesData: value.storesData)
    }

    /// Appends each value's encoding without checking that a store accepts it.
    func set(_ values: [HookArchivedText], to propertyListArray: inout [Any]) {
        guard let objects = try? values.map({ try archivedObject(for: $0.text, storesData: $0.storesData) }) else {
            return
        }

        propertyListArray.append(contentsOf: objects)
    }

    /// Writes the value's encoding without checking that a store accepts it.
    func set(_ dictionaryKey: String, to value: HookArchivedText, in propertyListDictionary: inout [String: Any]) {
        propertyListDictionary[dictionaryKey] = try? archivedObject(for: value.text, storesData: value.storesData)
    }
}

// MARK: - Proxied Archived Text Definition

/// A value proxied through ``HookArchivedText``.
private struct ProxiedArchivedText: Equatable, KeyValuePersistible {
    let base: HookArchivedText

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, HookArchivedText> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.base
            },
            from: {
                Self(base: $0)
            }
        )
    }
}
