//
//  MigrationCodecCoverageTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

private enum CoverageRaw: String {
    case one
}

private struct FailingPrimitive {
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension FailingPrimitive: PrimitiveKeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        throw PersistentKeyValueConversionError.invalidValue
    }

    static func get(from propertyListArray: [Any]) -> [Self]? {
        nil
    }

    static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        nil
    }

    static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        nil
    }

    @available(watchOS 9.0, *)
    static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    )
        -> Self?
    {
        nil
    }

    static func set(_ values: [Self], to propertyListArray: inout [Any]) {
    }

    static func set(
        _ dictionaryKey: String,
        to value: Self,
        in propertyListDictionary: inout [String: Any]
    ) {
    }

    static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
    }

    @available(watchOS 9.0, *)
    static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
    }

    func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        throw PersistentKeyValueConversionError.encodingFailed
    }
}

final class MigrationCodecCoverageTests: XCTestCase {
    // MARK: Tests

    func test_customPrimitive_failuresAndProxyRepresentationHelpers() throws {
        let primitive = PrimitivePersistentKeyValueRepresentation<FailingPrimitive>()

        XCTAssertThrowsError(try primitive.decode(storageObject: 1, format: .propertyList))
        XCTAssertThrowsError(
            try primitive.encode(FailingPrimitive(), format: .propertyList)
        )
        let key = PersistentKey(
            "legacy",
            defaultValue: 1,
            representation: ReferenceProxyPersistentKeyValueRepresentation<Int, String>(
                serializing: { _ in "value"

                },
                deserializing: { _ in
                    1
                }
            )
        )

        XCTAssertEqual(try decodeStorageValue(for: key, object: "value", format: .propertyList), 1)
        XCTAssertEqual(try encodeStorageValue(1, for: key, format: .propertyList) as? String, "value")
    }

    func test_dictionary_roundTripAndInvalidInput() throws {
        let representation = PrimitivePersistentKeyValueRepresentation<[String: String?]>()
        let object = try XCTUnwrap(
            try representation.encode(["a": "one", "b": nil], format: .propertyList)
        )
        let decoded: [String: String?] = try representation.decode(
            storageObject: object,
            format: .propertyList
        )

        XCTAssertEqual(decoded, ["a": "one"])
        XCTAssertThrowsError(
            try representation.decode(storageObject: ["a": 1], format: .propertyList)
        )

        XCTAssertThrowsError(try representation.decode(storageObject: [1], format: .propertyList))
        XCTAssertThrowsError(
            try representation.decode(storageObject: "wrong", format: .propertyList)
        )
    }

    func test_invalidScalarObjects_throw() {
        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<Bool>().decode(
                storageObject: "true",
                format: .propertyList
            )
        )

        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<Int>().decode(
                storageObject: "1",
                format: .propertyList
            )
        )

        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<Float>().decode(
                storageObject: "1",
                format: .propertyList
            )
        )

        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<Double>().decode(
                storageObject: "1",
                format: .propertyList
            )
        )

        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<String>().decode(
                storageObject: 1,
                format: .propertyList
            )
        )

        XCTAssertThrowsError(
            try PrimitivePersistentKeyValueRepresentation<Data>().decode(
                storageObject: "data",
                format: .propertyList
            )
        )
    }

    func test_optionalPrimitive_directCodec() throws {
        let representation = OptionalPersistentKeyValueRepresentation(
            PrimitivePersistentKeyValueRepresentation<String>()
        )
        let object = try XCTUnwrap(
            try representation.encode("value", format: .propertyList)
        )

        XCTAssertEqual(
            try representation.decode(storageObject: object, format: .propertyList),
            "value"
        )

        XCTAssertNil(try representation.encode(nil, format: .propertyList))
    }

    func test_propertyListStorage_freezeEqualityAndByteCount() throws {
        let url = URL(string: "https://example.com")!

        XCTAssertNoThrow(try PropertyListStorage.exactCopy(url, allowingLegacyURL: true))
        XCTAssertThrowsError(try PropertyListStorage.freeze(NSObject()))
        XCTAssertTrue(PropertyListStorage.equal(nil, nil))
        XCTAssertTrue(PropertyListStorage.equal(Double.nan, Double.nan))
        XCTAssertFalse(PropertyListStorage.equal(Double.nan, 1.0))
        XCTAssertFalse(PropertyListStorage.equal(1.0, Double.nan))
        XCTAssertTrue(PropertyListStorage.equal([1, 2], [1, 2]))
        XCTAssertFalse(PropertyListStorage.equal([1], [1, 2]))
        XCTAssertTrue(PropertyListStorage.equal(["a": 1], ["a": 1]))
        XCTAssertFalse(PropertyListStorage.equal(["a": 1], ["b": 1]))
        XCTAssertFalse(PropertyListStorage.equal(["a": 1], ["a": 1, "b": 2]))
        XCTAssertTrue(PropertyListStorage.equal(url, url))
        XCTAssertFalse(PropertyListStorage.equal(1, "1"))
        XCTAssertNoThrow(try PropertyListStorage.byteCount(["a": 1]))
        XCTAssertThrowsError(try PropertyListStorage.byteCount(NSObject()))
    }

    func test_proxyRawAndLosslessCodecs_succeed() throws {
        let proxy = ProxyPersistentKeyValueRepresentation<Int, Int>(
            to: {
                $0
            },
            from: {
                $0
            }
        )

        XCTAssertEqual(try proxy.decode(storageObject: 3, format: .propertyList), 3)
        XCTAssertEqual(try proxy.encode(3, format: .propertyList) as? Int, 3)

        let raw = RawRepresentablePersistentKeyValueRepresentation<CoverageRaw>()

        XCTAssertEqual(try raw.decode(storageObject: "one", format: .propertyList), .one)
        XCTAssertThrowsError(try raw.decode(storageObject: "other", format: .propertyList))
        XCTAssertEqual(try raw.encode(.one, format: .propertyList) as? String, "one")

        let lossless = LosslessStringConvertiblePersistentKeyValueRepresentation<Int>()

        XCTAssertEqual(try lossless.decode(storageObject: "3", format: .propertyList), 3)
        XCTAssertThrowsError(try lossless.decode(storageObject: "other", format: .propertyList))
        XCTAssertEqual(try lossless.encode(3, format: .propertyList) as? String, "3")
    }

    func test_urlInvalidObjectsAndWrongArchiveRoot_throw() throws {
        let representation = PrimitivePersistentKeyValueRepresentation<URL>()

        XCTAssertThrowsError(try representation.decode(storageObject: 1, format: .propertyList))
        XCTAssertThrowsError(try representation.decode(storageObject: 1, format: .userDefaults))

        let legacyURL = URL(string: "https://example.com/legacy")!

        XCTAssertEqual(
            try representation.decode(storageObject: legacyURL, format: .userDefaults),
            legacyURL
        )

        XCTAssertEqual(
            try representation.decode(storageObject: "path:name", format: .userDefaults).path,
            URL(fileURLWithPath: "path:name").path
        )
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: "wrong",
            requiringSecureCoding: true
        )

        XCTAssertThrowsError(
            try representation.decode(storageObject: archive, format: .userDefaults)
        )
    }
}
