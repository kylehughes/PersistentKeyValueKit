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

    func test_storablePropertyList_ofImmutablePropertyList_returnsSameObject() {
        let objects: [AnyObject] = [
            NSString(string: "a string long enough to need its own allocation"),
            NSNumber(value: 42),
            NSDate(),
            NSData(data: Data([1, 2])),
            NSArray(array: ["text", NSArray(array: [1])]),
            NSDictionary(dictionary: ["a": NSDictionary(dictionary: ["b": "c"])]),
        ]

        for object in objects {
            XCTAssertTrue(storablePropertyList(object) === object, "\(object)")
        }
    }

    func test_storablePropertyList_ofMutableContainers_returnsImmutableCopies() throws {
        let array = NSMutableArray(array: ["element"])
        let dictionary = NSMutableDictionary(dictionary: ["key": "value"])

        let arraySnapshot = try XCTUnwrap(storablePropertyList(array))
        let dictionarySnapshot = try XCTUnwrap(storablePropertyList(dictionary))

        array.add(try archiveUID())
        dictionary["uid"] = try archiveUID()

        XCTAssertFalse(arraySnapshot === array)
        XCTAssertFalse(dictionarySnapshot === dictionary)
        XCTAssertEqual(arraySnapshot as? [String], ["element"])
        XCTAssertEqual(dictionarySnapshot as? [String: String], ["key": "value"])
        XCTAssertTrue(isStorablePropertyList(arraySnapshot))
        XCTAssertTrue(isStorablePropertyList(dictionarySnapshot))
    }

    func test_storablePropertyList_ofMutableLeaves_returnsImmutableCopies() throws {
        let string = NSMutableString(string: "text")
        let data = NSMutableData(data: Data([1]))

        let stringSnapshot = try XCTUnwrap(storablePropertyList(string))
        let dataSnapshot = try XCTUnwrap(storablePropertyList(data))

        string.setString("changed")
        data.setData(Data([2]))

        XCTAssertFalse(stringSnapshot === string)
        XCTAssertFalse(dataSnapshot === data)
        XCTAssertEqual(stringSnapshot as? String, "text")
        XCTAssertEqual(dataSnapshot as? Data, Data([1]))
    }

    func test_storablePropertyList_ofImmutableContainersOfMutableLeaves_copiesThemAtAnyDepth() throws {
        let string = NSMutableString(string: "text")
        let data = NSMutableData(data: Data([1]))
        let array = NSArray(array: ["first", string, NSArray(array: [data])])
        let dictionary = NSDictionary(dictionary: ["first": "value", "data": NSDictionary(dictionary: ["leaf": data])])

        let arraySnapshot = try XCTUnwrap(storablePropertyList(array) as? NSArray)
        let dictionarySnapshot = try XCTUnwrap(storablePropertyList(dictionary) as? NSDictionary)

        string.setString("changed")
        data.setData(Data([2]))

        XCTAssertFalse(arraySnapshot === array)
        XCTAssertFalse(dictionarySnapshot === dictionary)
        XCTAssertEqual(arraySnapshot, ["first", "text", [Data([1])]] as NSArray)
        XCTAssertEqual(dictionarySnapshot, ["first": "value", "data": ["leaf": Data([1])]] as NSDictionary)
    }

    func test_storableEncoding_ofSwiftLeaves_returnsValuesThemselves() throws {
        let values: [Any] = ["text", 42, 1.5, true, Data([1]), Date(timeIntervalSinceReferenceDate: 0)]

        for value in values {
            let encoding = try XCTUnwrap(storableEncoding(value), "\(value)")
            guard case .store(let object) = encoding else {
                XCTFail("\(value)")
                continue
            }

            XCTAssertTrue(type(of: object) == type(of: value), "\(value)")
            XCTAssertTrue(isStorablePropertyList(value), "\(value)")
        }
    }

    func test_isStorableDictionary_ofStorableEntries_replacesMutableEntriesWithCopies() {
        let buffer = NSMutableDictionary(dictionary: ["field": "value"])
        let leaf = NSMutableString(string: "text")
        var objects: [String: Any] = ["plain": "value", "buffer": buffer, "leaf": leaf]

        XCTAssertTrue(isStorableDictionary(&objects))

        buffer["uid"] = "changed"
        leaf.setString("changed")

        XCTAssertEqual(objects["plain"] as? String, "value")
        XCTAssertEqual(objects["buffer"] as? NSDictionary, ["field": "value"] as NSDictionary)
        XCTAssertEqual(objects["leaf"] as? String, "text")
    }

    func test_isStorableDictionary_ofArchiveUIDEntry_returnsFalse() throws {
        let buffer = NSMutableDictionary(dictionary: ["field": "value"])
        var objects: [String: Any] = ["buffer": buffer, "archive": try archivedPropertyList()]

        XCTAssertFalse(isStorableDictionary(&objects))
        XCTAssertTrue(objects["buffer"] as? NSMutableDictionary === buffer)
    }

    func test_storablePropertyList_ofImmutableContainersOfMutableObjects_copiesThemAtAnyDepth() throws {
        let buffer = NSMutableDictionary(dictionary: ["field": "value"])
        let list = NSMutableArray(array: ["element"])
        let array = NSArray(array: ["first", buffer, "middle", list])
        let dictionary = NSDictionary(dictionary: ["first": "value", "buffer": NSArray(array: [buffer])])

        let arraySnapshot = try XCTUnwrap(storablePropertyList(array) as? NSArray)
        let dictionarySnapshot = try XCTUnwrap(storablePropertyList(dictionary) as? NSDictionary)

        buffer["uid"] = try archiveUID()
        list.add(try archiveUID())

        XCTAssertFalse(arraySnapshot === array)
        XCTAssertFalse(dictionarySnapshot === dictionary)
        XCTAssertEqual(arraySnapshot, ["first", ["field": "value"], "middle", ["element"]] as NSArray)
        XCTAssertEqual(dictionarySnapshot, ["first": "value", "buffer": [["field": "value"]]] as NSDictionary)
        XCTAssertTrue(isStorablePropertyList(arraySnapshot))
        XCTAssertTrue(isStorablePropertyList(dictionarySnapshot))
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

// MARK: - Shared Encoding Buffer Tests

extension StorablePropertyListTests {
    func test_userDefaultsCollectionWrites_ofEncoderThatChangesEarlierOutput_storeEachEncodingAsReturned() {
        for storesData in [false, true] {
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).dictionary",
                writing: { ["first": $0[0], "second": $0[1]] },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).nestedArray",
                writing: { [[$0[0]], [$0[1]]] },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).array",
                writing: { $0 },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).dictionaryOfArrays",
                writing: { ["first": [$0[0]], "second": [$0[1]]] },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).optionalDictionary",
                writing: { ["first": Optional($0[0]), "second": Optional($0[1])] },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).proxyDictionary",
                writing: { ["first": ProxiedBufferedText(base: $0[0]), "second": ProxiedBufferedText(base: $0[1])] },
                storesData: storesData
            )
        }
    }

    func test_userDefaultsCollectionWrites_ofContainerHooksThatChangeEarlierOutput_storeEachEncodingAsReturned() {
        for storesData in [false, true] {
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).dictionary",
                writing: { ["first": $0[0], "second": $0[1]].mapValues(HookBufferedText.init(base:)) },
                storesData: storesData
            )
            assertUserDefaultsWritesStoreEachEncoding(
                "key:\(#function).\(storesData).nestedArray",
                writing: { [[$0[0]], [$0[1]]].map { $0.map(HookBufferedText.init(base:)) } },
                storesData: storesData
            )
        }
    }

    func test_ubiquitousStoreCollectionWrites_ofEncoderThatChangesEarlierOutput_storeEachEncodingAsReturned() throws {
        let store = MockUbiquitousKeyValueStore()
        let dictionaryKey = PersistentKey("key:\(#function).dictionary", defaultValue: [String: BufferedText]())
        let nestedKey = PersistentKey("key:\(#function).nestedArray", defaultValue: [[BufferedText]]())
        let dictionaryValues = BufferedText.encodedTogether(["one", "two"], storesData: false)
        let nestedValues = BufferedText.encodedTogether(["one", "two"], storesData: false)

        store.set(dictionaryKey, to: ["first": dictionaryValues[0], "second": dictionaryValues[1]])
        store.set(nestedKey, to: [[nestedValues[0]], [nestedValues[1]]])

        for id in [dictionaryKey.id, nestedKey.id] {
            let object = try XCTUnwrap(store.object(forKey: id))

            XCTAssertTrue(isStorablePropertyList(object), id)
            XCTAssertFalse(containsMetadata(object), id)
        }

        XCTAssertEqual(store.get(dictionaryKey), ["first": dictionaryValues[0], "second": dictionaryValues[1]])
        XCTAssertEqual(store.get(nestedKey), [[nestedValues[0]], [nestedValues[1]]])
    }
}

// MARK: - Reused Leaf Buffer Tests

extension StorablePropertyListTests {
    func test_userDefaultsCollectionWrites_ofEncoderThatReusesStringBuffer_storeEachEncoding() {
        assertUserDefaultsWritesStoreEachReusedBufferEncoding("key:\(#function)", through: ReusedString.self)
    }

    func test_userDefaultsCollectionWrites_ofEncoderThatReusesDataBuffer_storeEachEncoding() {
        assertUserDefaultsWritesStoreEachReusedBufferEncoding("key:\(#function)", through: ReusedData.self)
    }

    func test_userDefaultsCollectionWrites_ofEncoderThatWrapsReusedStringBuffer_storeEachEncoding() {
        assertUserDefaultsWritesStoreEachReusedBufferEncoding("key:\(#function)", through: WrappedReusedString.self)
    }

    func test_userDefaultsCollectionWrites_ofEncoderThatWrapsReusedDataBuffer_storeEachEncoding() {
        assertUserDefaultsWritesStoreEachReusedBufferEncoding("key:\(#function)", through: WrappedReusedData.self)
    }

    func test_ubiquitousStoreCollectionWrites_ofEncoderThatReusesBuffer_storeEachEncoding() {
        let store = MockUbiquitousKeyValueStore()
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [ReusedBufferText<ReusedData>]())
        let dictionaryKey = PersistentKey(
            "key:\(#function).dictionary",
            defaultValue: [String: ReusedBufferText<ReusedString>]()
        )

        store.set(arrayKey, to: [ReusedBufferText("one"), ReusedBufferText("two")])
        store.set(dictionaryKey, to: ["first": ReusedBufferText("one"), "second": ReusedBufferText("two")])

        XCTAssertEqual(store.get(arrayKey), [ReusedBufferText("one"), ReusedBufferText("two")])
        XCTAssertEqual(store.get(dictionaryKey), ["first": ReusedBufferText("one"), "second": ReusedBufferText("two")])
    }

    func test_checkedEncode_ofEncoderThatReusesBuffer_encodesEachEncoding() throws {
        try assertCheckedEncodingKeepsEachEncoding(through: ReusedString.self)
        try assertCheckedEncodingKeepsEachEncoding(through: ReusedData.self)
        try assertCheckedEncodingKeepsEachEncoding(through: WrappedReusedString.self)
        try assertCheckedEncodingKeepsEachEncoding(through: WrappedReusedData.self)
    }
}

// MARK: - Earlier Entry Change Tests

extension StorablePropertyListTests {
    func test_userDefaultsDictionaryWrites_ofHookThatAddsArchiveToEarlierEntry_leavePreviousValues() {
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).dictionary",
            writing: { ["first": $0[0], "second": $0[1]] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).optionalDictionary",
            writing: { ["first": Optional($0[0]), "second": Optional($0[1])] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).doubleOptionalDictionary",
            writing: { ["first": Optional(Optional($0[0])), "second": Optional(Optional($0[1]))] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).proxyDictionary",
            writing: { ["first": ProxiedSchemaText(base: $0[0]), "second": ProxiedSchemaText(base: $0[1])] },
            previous: ["entry": "previous"]
        )
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).arrayOfDictionaries",
            writing: { [["first": $0[0], "second": $0[1]]] },
            previous: [["entry": "previous"]]
        )
        assertUserDefaultsSchemaWritesKeepPreviousValue(
            "key:\(#function).dictionaryOfDictionaries",
            writing: { ["entry": ["first": $0[0], "second": $0[1]]] },
            previous: ["entry": ["entry": "previous"]]
        )
    }

    func test_ubiquitousStoreDictionaryWrite_ofHookThatAddsArchiveToEarlierEntry_leavesPreviousValue() {
        let store = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: [String: SchemaText]())
        let control = SchemaText.pair(storesData: true)

        store.set(["entry": "previous"], forKey: key.id)
        store.set(key, to: SchemaText.pair(storesData: false))

        XCTAssertEqual(store.dictionary(forKey: key.id) as? [String: String], ["entry": "previous"])

        store.set(key, to: control)

        XCTAssertEqual(store.get(key), control)
    }

    func test_propertyListDictionaryWrite_ofHookThatAddsArchiveToEarlierEntry_leavesContainerUnchanged() {
        let representation = [String: SchemaText].persistentKeyValueRepresentation
        let control = SchemaText.pair(storesData: true)
        var dictionary: [String: Any] = ["entry": "previous"]

        representation.set("entry", to: SchemaText.pair(storesData: false), in: &dictionary)

        XCTAssertEqual(dictionary as? [String: String], ["entry": "previous"])

        representation.set("entry", to: control, in: &dictionary)

        XCTAssertEqual(representation.get("entry", from: dictionary), control)
    }

    func test_checkedEncode_ofHookThatAddsArchiveToEarlierEntry_throwsEncodingFailed() throws {
        let candidate = SchemaText.pair(storesData: false)
        let control = SchemaText.pair(storesData: true)
        let formats: [PersistentKeyValueStorageFormat] = [.userDefaults, .ubiquitousKeyValueStore, .propertyList]

        for format in formats {
            assertEncodingFails(candidate, format: format)
            assertEncodingFails(candidate.mapValues(Optional.some), format: format)
            assertEncodingFails([candidate], format: format)
            assertEncodingFails(candidate.mapValues(ProxiedSchemaText.init(base:)), format: format)

            let object = try XCTUnwrap(control.encode(format: format), "\(format)")

            XCTAssertTrue(isStorablePropertyList(object), "\(format)")
            XCTAssertEqual(try [String: SchemaText].decode(storageObject: object, format: format), control)
        }
    }
}

// MARK: - Checked Encoding Tests

extension StorablePropertyListTests {
    func test_checkedEncode_ofCustomArchivePropertyLists_throwsEncodingFailed() {
        let candidate = HookArchivedText("candidate", storesData: false)
        let formats: [PersistentKeyValueStorageFormat] = [.userDefaults, .ubiquitousKeyValueStore, .propertyList]

        for format in formats {
            assertEncodingFails([candidate], format: format)
            assertEncodingFails(["entry": candidate], format: format)
            assertEncodingFails([HookArchivedText("control", storesData: true), candidate], format: format)
            assertEncodingFails([[candidate]], format: format)
            assertEncodingFails(["entry": [candidate]], format: format)
            assertEncodingFails([Optional(candidate)], format: format)
            assertEncodingFails(["entry": ProxiedArchivedText(base: candidate)], format: format)
        }
    }

    func test_checkedEncode_ofCustomArchiveData_encodesStorableObjects() throws {
        let control = HookArchivedText("control", storesData: true)
        let array = try XCTUnwrap(
            [HookArchivedText].persistentKeyValueRepresentation.encode([control], format: .userDefaults)
        )
        let dictionary = try XCTUnwrap(
            [String: HookArchivedText].persistentKeyValueRepresentation.encode(
                ["entry": control],
                format: .userDefaults
            )
        )

        XCTAssertTrue(isStorablePropertyList(array))
        XCTAssertTrue(isStorablePropertyList(dictionary))
        XCTAssertEqual(
            try [HookArchivedText].persistentKeyValueRepresentation.decode(storageObject: array, format: .userDefaults),
            [control]
        )
        XCTAssertEqual(
            try [String: HookArchivedText].persistentKeyValueRepresentation.decode(
                storageObject: dictionary,
                format: .userDefaults
            ),
            ["entry": control]
        )
    }

    func test_checkedEncode_ofEncoderThatChangesEarlierOutput_encodesEachEncodingAsReturned() throws {
        let dictionaryValues = BufferedText.encodedTogether(["one", "two"], storesData: false)
        let nestedValues = BufferedText.encodedTogether(["one", "two"], storesData: false)
        let hookValues = BufferedText.encodedTogether(["one", "two"], storesData: false).map(HookBufferedText.init)
        let objects = [
            try XCTUnwrap(
                [String: BufferedText].persistentKeyValueRepresentation.encode(
                    ["first": dictionaryValues[0], "second": dictionaryValues[1]],
                    format: .userDefaults
                )
            ),
            try XCTUnwrap(
                [[BufferedText]].persistentKeyValueRepresentation.encode(
                    [[nestedValues[0]], [nestedValues[1]]],
                    format: .userDefaults
                )
            ),
            try XCTUnwrap(
                [[HookBufferedText]].persistentKeyValueRepresentation.encode(
                    [[hookValues[0]], [hookValues[1]]],
                    format: .userDefaults
                )
            ),
        ]

        for object in objects {
            XCTAssertTrue(isStorablePropertyList(object), "\(object)")
            XCTAssertFalse(containsMetadata(object), "\(object)")
        }
    }
}

// MARK: - Archive UID Comparison Tests

extension StorablePropertyListTests {
    func test_equal_comparesArchiveUIDsByValue() throws {
        let uids = try arrayArchiveUIDs()

        XCTAssertTrue(PropertyListStorage.equal(try archiveUID(), try archiveUID()))
        XCTAssertTrue(PropertyListStorage.equal(try archivedPropertyList(), try archivedPropertyList()))
        XCTAssertFalse(PropertyListStorage.equal(uids[0], uids[1]))
        XCTAssertFalse(PropertyListStorage.equal(uids[0], nil))
        XCTAssertFalse(PropertyListStorage.equal(nil, uids[0]))
        XCTAssertFalse(PropertyListStorage.equal(uids[0], 2))
        XCTAssertFalse(PropertyListStorage.equal(NSNull(), NSNull()))
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
        XCTAssertTrue(PropertyListStorage.equal(destination.get(key), archive))
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
        XCTAssertTrue(PropertyListStorage.equal(destination.get(key), archive))
        XCTAssertTrue(PropertyListStorage.equal(source.get(key), archive))
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

    /// Asserts that a write of values whose encoder adds metadata to the dictionary it returned for the first value
    /// while encoding the second stores each encoding as the encoder returned it.
    private func assertUserDefaultsWritesStoreEachEncoding<Value: Equatable & KeyValuePersistible & Sendable>(
        _ id: String,
        writing value: ([BufferedText]) -> Value,
        storesData: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let texts = BufferedText.encodedTogether(["one", "two"], storesData: storesData)
        let key = PersistentKey(id, defaultValue: value([BufferedText("fallback"), BufferedText("fallback")]))

        userDefaults.set("previous", forKey: key.id)
        userDefaults.set(key, to: value(texts))

        let object = userDefaults.object(forKey: key.id)

        XCTAssertTrue(texts[0].buffer?.hasAddedMetadata == true, file: file, line: line)
        XCTAssertNotNil(object, file: file, line: line)
        XCTAssertFalse(containsMetadata(object), file: file, line: line)
        XCTAssertEqual(userDefaults.get(key), value(texts), file: file, line: line)
    }

    /// Asserts that checked encoding of `value` throws ``PersistentKeyValueConversionError/encodingFailed``.
    private func assertEncodingFails<Value: KeyValuePersistible>(
        _ value: Value,
        format: PersistentKeyValueStorageFormat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try Value.persistentKeyValueRepresentation.encode(value, format: format),
            "\(Value.self), \(format)",
            file: file,
            line: line
        ) {
            XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed, file: file, line: line)
        }
    }

    /// Asserts that writes of collections of two values, which `Kind`'s buffer encodes in turn, store each encoding,
    /// whether the protocol's default container methods or custom ones write them.
    ///
    /// A custom array method that encodes both values in one call changes its own result before it returns, so the
    /// custom methods write the values in separate calls.
    private func assertUserDefaultsWritesStoreEachReusedBufferEncoding<Kind: ReusedLeafBufferKind>(
        _ id: String,
        through kind: Kind.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let one = ReusedBufferText<Kind>("one")
        let two = ReusedBufferText<Kind>("two")
        let hookOne = HookReusedBufferText(base: one)
        let hookTwo = HookReusedBufferText(base: two)

        assertUserDefaultsWriteStores("\(id).array", [one, two], file: file, line: line)
        assertUserDefaultsWriteStores("\(id).dictionary", ["first": one, "second": two], file: file, line: line)
        assertUserDefaultsWriteStores("\(id).nestedArray", [[one], [two]], file: file, line: line)
        assertUserDefaultsWriteStores(
            "\(id).arrayOfDictionaries",
            [["first": one], ["second": two]],
            file: file,
            line: line
        )
        assertUserDefaultsWriteStores(
            "\(id).dictionaryOfArrays",
            ["first": [one], "second": [two]],
            file: file,
            line: line
        )
        assertUserDefaultsWriteStores("\(id).optionalArray", [Optional(one), Optional(two)], file: file, line: line)
        assertUserDefaultsWriteStores(
            "\(id).optionalDictionary",
            ["first": Optional(one), "second": Optional(two)],
            file: file,
            line: line
        )
        assertUserDefaultsWriteStores(
            "\(id).hookDictionary",
            ["first": hookOne, "second": hookTwo],
            file: file,
            line: line
        )
        assertUserDefaultsWriteStores("\(id).hookNestedArray", [[hookOne], [hookTwo]], file: file, line: line)
    }

    /// Asserts that a write of `value` stores an object that decodes as `value`.
    private func assertUserDefaultsWriteStores<Value: Equatable & KeyValuePersistible & Sendable>(
        _ id: String,
        _ value: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let key = PersistentKey(id, defaultValue: value)

        userDefaults.set(key, to: value)

        guard let object = userDefaults.object(forKey: key.id) else {
            return XCTFail("\(id) is absent", file: file, line: line)
        }

        XCTAssertEqual(
            try Value.persistentKeyValueRepresentation.decode(storageObject: object, format: .userDefaults),
            value,
            id,
            file: file,
            line: line
        )
    }

    /// Asserts that checked encodings of collections of two values, which `Kind`'s buffer encodes in turn, keep each
    /// encoding after the buffer changes.
    private func assertCheckedEncodingKeepsEachEncoding<Kind: ReusedLeafBufferKind>(
        through kind: Kind.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = [ReusedBufferText<Kind>("one"), ReusedBufferText<Kind>("two")]
        let dictionary = ["first": values[0], "second": values[1]]
        let hookValues = values.map { [HookReusedBufferText(base: $0)] }
        let arrayObject = try XCTUnwrap(values.encode(format: .userDefaults), file: file, line: line)
        let dictionaryObject = try XCTUnwrap(dictionary.encode(format: .userDefaults), file: file, line: line)
        let hookObject = try XCTUnwrap(hookValues.encode(format: .userDefaults), file: file, line: line)

        _ = Kind.buffer.object(for: "late")

        XCTAssertEqual(
            try [ReusedBufferText<Kind>].decode(storageObject: arrayObject, format: .userDefaults),
            values,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try [String: ReusedBufferText<Kind>].decode(storageObject: dictionaryObject, format: .userDefaults),
            dictionary,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try [[HookReusedBufferText<Kind>]].decode(storageObject: hookObject, format: .userDefaults),
            hookValues,
            file: file,
            line: line
        )
    }

    /// Asserts that a dictionary write whose container method adds an archive's property list to an earlier entry
    /// leaves the previous value, and that a write whose method adds the archive as `Data` stores it.
    private func assertUserDefaultsSchemaWritesKeepPreviousValue<Value: Equatable & KeyValuePersistible & Sendable>(
        _ id: String,
        writing value: ([SchemaText]) -> Value,
        previous: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let control = value(SchemaText.texts(storesData: true))
        let key = PersistentKey(id, defaultValue: control)

        userDefaults.set(previous, forKey: key.id)
        userDefaults.set(key, to: value(SchemaText.texts(storesData: false)))

        XCTAssertEqual(userDefaults.object(forKey: key.id) as? NSObject, previous as? NSObject, file: file, line: line)

        userDefaults.removeObject(forKey: key.id)
        userDefaults.set(key, to: control)

        XCTAssertTrue(containsMetadata(userDefaults.object(forKey: key.id), named: "schema"), file: file, line: line)
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

    func test_userDefaultsMove_ofEncoderThatReusesBuffer_movesEachRecord() throws {
        let destinationSuiteName = stableSuiteName("PersistentKeyValueKitTests.StorablePropertyList.destination")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: destinationSuiteName))
        let arrayKey = PersistentKey("key:\(#function).array", defaultValue: [ReusedBufferText<ReusedData>]())
        let dictionaryKey = PersistentKey(
            "key:\(#function).dictionary",
            defaultValue: [String: ReusedBufferText<ReusedString>]()
        )

        defer {
            destination.removePersistentDomain(forName: destinationSuiteName)
        }

        userDefaults.set(["one", "two"], forKey: arrayKey.id)
        userDefaults.set(["first": "one", "second": "two"], forKey: dictionaryKey.id)

        let report = try userDefaults.move(
            [arrayKey, dictionaryKey] as [any PersistentKeyProtocol],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertEqual(report.completion, .recorded)
        XCTAssertNil(userDefaults.object(forKey: arrayKey.id))
        XCTAssertNil(userDefaults.object(forKey: dictionaryKey.id))
        XCTAssertEqual(destination.get(arrayKey), [ReusedBufferText("one"), ReusedBufferText("two")])
        XCTAssertEqual(
            destination.get(dictionaryKey),
            ["first": ReusedBufferText("one"), "second": ReusedBufferText("two")]
        )
    }

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

/// Returns whether `object` holds a dictionary with metadata at `name`, such as the metadata that
/// ``SharedEncodingBuffer`` adds, at any depth.
private func containsMetadata(_ object: Any?, named name: String = "metadata") -> Bool {
    switch object {
    case let dictionary as [String: Any]:
        dictionary[name] != nil || dictionary.values.contains { containsMetadata($0, named: name) }
    case let array as [Any]:
        array.contains { containsMetadata($0, named: name) }
    default:
        false
    }
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

    func get(from store: NSUbiquitousKeyValueStore) -> NSDictionary {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSDictionary, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

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

// MARK: - Shared Encoding Buffer Definition

/// A mutable dictionary that an encoder returns for the first text it encodes and, while encoding each later text,
/// adds metadata to: a keyed archive, either as its property list or as its `Data`.
private final class SharedEncodingBuffer: @unchecked Sendable {
    /// Whether the metadata is stored as an archive's `Data` rather than as its property list.
    let storesData: Bool

    private let dictionary = NSMutableDictionary()
    private let lock = NSLock()
    private var hasEncoded = false

    // MARK: Initialization

    init(storesData: Bool) {
        self.storesData = storesData
    }

    // MARK: Instance Interface

    /// Whether encoding a later text has added metadata to the dictionary.
    var hasAddedMetadata: Bool {
        lock.withLock {
            dictionary["metadata"] != nil
        }
    }

    /// Returns the dictionary, holding `text`, for the first text, or adds metadata to the dictionary and returns
    /// `text` for each later text.
    func object(for text: String) throws -> Any {
        try lock.withLock {
            guard hasEncoded else {
                hasEncoded = true
                dictionary["text"] = text
                return dictionary
            }

            dictionary["metadata"] = try archivedObject(for: "metadata", storesData: storesData)
            return text
        }
    }
}

// MARK: - Buffered Text Definition

/// A string whose representation encodes it through a ``SharedEncodingBuffer``, if it has one, with the protocol's
/// default container methods.
private struct BufferedText: Equatable, KeyValuePersistible {
    let text: String
    let buffer: SharedEncodingBuffer?

    // MARK: Initialization

    init(_ text: String, buffer: SharedEncodingBuffer? = nil) {
        self.text = text
        self.buffer = buffer
    }

    // MARK: Static Interface

    /// Returns `texts` encoded through one buffer, in order.
    static func encodedTogether(_ texts: [String], storesData: Bool) -> [Self] {
        let buffer = SharedEncodingBuffer(storesData: storesData)

        return texts.map {
            Self($0, buffer: buffer)
        }
    }

    // MARK: Equatable Implementation

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: BufferedTextRepresentation {
        BufferedTextRepresentation()
    }
}

private struct BufferedTextRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> BufferedText {
        guard let text = storageObject as? String ?? (storageObject as? [String: Any])?["text"] as? String else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return BufferedText(text)
    }

    func encode(_ value: BufferedText, format: PersistentKeyValueStorageFormat) throws -> Any? {
        try value.buffer?.object(for: value.text) ?? value.text
    }
}

// MARK: - Hook Buffered Text Definition

/// A ``BufferedText`` whose representation writes collections with its own container methods, which store each
/// encoding as the encoder returns it.
private struct HookBufferedText: Equatable, KeyValuePersistible {
    let base: BufferedText

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: HookBufferedTextRepresentation {
        HookBufferedTextRepresentation()
    }
}

private struct HookBufferedTextRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> HookBufferedText {
        HookBufferedText(base: try BufferedTextRepresentation().decode(storageObject: storageObject, format: format))
    }

    func encode(_ value: HookBufferedText, format: PersistentKeyValueStorageFormat) throws -> Any? {
        try BufferedTextRepresentation().encode(value.base, format: format)
    }

    /// Appends each value's encoding without checking that a store accepts it.
    func set(_ values: [HookBufferedText], to propertyListArray: inout [Any]) {
        guard let objects = try? values.map({ try encode($0, format: .propertyList) }) else {
            return
        }

        propertyListArray.append(contentsOf: objects.compactMap { $0 })
    }

    /// Writes the value's encoding without checking that a store accepts it.
    func set(_ dictionaryKey: String, to value: HookBufferedText, in propertyListDictionary: inout [String: Any]) {
        propertyListDictionary[dictionaryKey] = try? encode(value, format: .propertyList)
    }
}

// MARK: - Proxied Buffered Text Definition

/// A value proxied through ``BufferedText``.
private struct ProxiedBufferedText: Equatable, KeyValuePersistible {
    let base: BufferedText

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, BufferedText> {
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

// MARK: - Reused Leaf Buffer Definition

/// A mutable string or data object that an encoder overwrites with each text it encodes and returns, either itself or
/// in a new immutable dictionary.
private final class ReusedLeafBuffer: @unchecked Sendable {
    /// Whether the buffer is returned in a new immutable dictionary rather than itself.
    let isWrapped: Bool

    /// The `NSMutableData` or `NSMutableString` that holds the latest text.
    private let buffer: NSObject
    private let lock = NSLock()

    // MARK: Initialization

    init(isData: Bool, isWrapped: Bool) {
        self.buffer = isData ? NSMutableData() : NSMutableString()
        self.isWrapped = isWrapped
    }

    // MARK: Instance Interface

    /// Overwrites the buffer with `text` and returns it.
    func object(for text: String) -> Any {
        lock.withLock {
            if let data = buffer as? NSMutableData {
                data.setData(Data(text.utf8))
            } else if let string = buffer as? NSMutableString {
                string.setString(text)
            }

            return isWrapped ? NSDictionary(object: buffer, forKey: "text" as NSString) : buffer
        }
    }
}

/// A type whose ``buffer`` encodes every ``ReusedBufferText`` of that type.
private protocol ReusedLeafBufferKind {
    static var buffer: ReusedLeafBuffer { get }
}

private enum ReusedString: ReusedLeafBufferKind {
    static let buffer = ReusedLeafBuffer(isData: false, isWrapped: false)
}

private enum ReusedData: ReusedLeafBufferKind {
    static let buffer = ReusedLeafBuffer(isData: true, isWrapped: false)
}

private enum WrappedReusedString: ReusedLeafBufferKind {
    static let buffer = ReusedLeafBuffer(isData: false, isWrapped: true)
}

private enum WrappedReusedData: ReusedLeafBufferKind {
    static let buffer = ReusedLeafBuffer(isData: true, isWrapped: true)
}

// MARK: - Reused Buffer Text Definition

/// A string whose representation encodes it through `Kind`'s buffer, with the protocol's default container methods.
private struct ReusedBufferText<Kind: ReusedLeafBufferKind>: Equatable, KeyValuePersistible {
    let text: String

    // MARK: Initialization

    init(_ text: String) {
        self.text = text
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: ReusedBufferTextRepresentation<Kind> {
        ReusedBufferTextRepresentation()
    }
}

private struct ReusedBufferTextRepresentation<Kind: ReusedLeafBufferKind>: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> ReusedBufferText<Kind> {
        let object = (storageObject as? [String: Any])?["text"] ?? storageObject

        if let text = object as? String {
            return ReusedBufferText(text)
        }

        guard let data = object as? Data, let text = String(data: data, encoding: .utf8) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return ReusedBufferText(text)
    }

    func encode(_ value: ReusedBufferText<Kind>, format: PersistentKeyValueStorageFormat) throws -> Any? {
        Kind.buffer.object(for: value.text)
    }
}

// MARK: - Hook Reused Buffer Text Definition

/// A ``ReusedBufferText`` whose representation writes collections with its own container methods, which store each
/// encoding as the buffer returns it.
private struct HookReusedBufferText<Kind: ReusedLeafBufferKind>: Equatable, KeyValuePersistible {
    let base: ReusedBufferText<Kind>

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: HookReusedBufferTextRepresentation<Kind> {
        HookReusedBufferTextRepresentation()
    }
}

private struct HookReusedBufferTextRepresentation<Kind: ReusedLeafBufferKind>: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> HookReusedBufferText<Kind> {
        HookReusedBufferText(
            base: try ReusedBufferTextRepresentation().decode(storageObject: storageObject, format: format)
        )
    }

    func encode(_ value: HookReusedBufferText<Kind>, format: PersistentKeyValueStorageFormat) throws -> Any? {
        Kind.buffer.object(for: value.base.text)
    }

    /// Appends each value's encoding without copying it.
    func set(_ values: [HookReusedBufferText<Kind>], to propertyListArray: inout [Any]) {
        propertyListArray.append(contentsOf: values.map { Kind.buffer.object(for: $0.base.text) })
    }

    /// Writes the value's encoding without copying it.
    func set(
        _ dictionaryKey: String,
        to value: HookReusedBufferText<Kind>,
        in propertyListDictionary: inout [String: Any]
    ) {
        propertyListDictionary[dictionaryKey] = Kind.buffer.object(for: value.base.text)
    }
}

// MARK: - Schema Text Definition

/// A string whose representation, while writing a later dictionary entry, adds schema metadata to an entry that it
/// wrote earlier: a keyed archive, either as its property list or as its `Data`.
private struct SchemaText: Equatable, KeyValuePersistible {
    let text: String

    /// Whether writing this value adds the metadata as an archive's `Data` rather than as its property list.
    let storesData: Bool

    // MARK: Initialization

    init(_ text: String, storesData: Bool) {
        self.text = text
        self.storesData = storesData
    }

    // MARK: Static Interface

    /// Returns two texts whose writes add the metadata as `Data` if `storesData`.
    static func texts(storesData: Bool) -> [Self] {
        [Self("one", storesData: storesData), Self("two", storesData: storesData)]
    }

    /// Returns ``texts(storesData:)`` keyed by position.
    static func pair(storesData: Bool) -> [String: Self] {
        let texts = texts(storesData: storesData)

        return ["first": texts[0], "second": texts[1]]
    }

    // MARK: Equatable Implementation

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: SchemaTextRepresentation {
        SchemaTextRepresentation()
    }
}

private struct SchemaTextRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> SchemaText {
        guard let text = storageObject as? String ?? (storageObject as? [String: Any])?["text"] as? String else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return SchemaText(text, storesData: false)
    }

    func encode(_ value: SchemaText, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value.text
    }

    /// Writes the value's text, then adds the metadata to an entry that an earlier call wrote, without checking that a
    /// store accepts it.
    func set(_ dictionaryKey: String, to value: SchemaText, in propertyListDictionary: inout [String: Any]) {
        let earlierKey = propertyListDictionary.keys.first {
            $0 != dictionaryKey
        }

        propertyListDictionary[dictionaryKey] = value.text

        guard
            let earlierKey,
            let earlierText = propertyListDictionary[earlierKey] as? String,
            let schema = try? archivedObject(for: "schema", storesData: value.storesData)
        else {
            return
        }

        propertyListDictionary[earlierKey] = ["text": earlierText, "schema": schema]
    }
}

// MARK: - Proxied Schema Text Definition

/// A value proxied through ``SchemaText``.
private struct ProxiedSchemaText: Equatable, KeyValuePersistible {
    let base: SchemaText

    // MARK: KeyValuePersistible Implementation

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, SchemaText> {
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
