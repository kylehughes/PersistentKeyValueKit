import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

private struct MigrationUnencodableValue: Sendable {
    let rawValue: String
}

// MARK: - KeyValuePersistible Extension

extension MigrationUnencodableValue: KeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(
            to: { _ in
                nil as String?
            },
            from: {
                MigrationUnencodableValue(rawValue: $0)
            }
        )
    }
}

// MARK: - Migration Unreadable Value Definition

private struct MigrationUnreadableValue: Sendable {
    let rawValue: String
}

// MARK: - KeyValuePersistible Extension

extension MigrationUnreadableValue: KeyValuePersistible {
    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, String> {
        ProxyPersistentKeyValueRepresentation(
            to: \.rawValue,
            from: { _ in
                nil
            }
        )
    }
}

private struct MigrationPayload: Codable, Sendable {
    let value: String
}

private struct MigrationEncodingError: Error, Equatable {
}

private struct MigrationThrowingEncoder: Sendable {
}

// MARK: - TopLevelEncoder Extension

extension MigrationThrowingEncoder: TopLevelEncoder {
    typealias Output = Data

    func encode<T>(_ value: T) throws -> Data where T: Encodable {
        throw MigrationEncodingError()
    }
}

final class MigrationRepresentationTests: XCTestCase {
    // MARK: Tests

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    func testCodableDecodePreservesUnderlyingError() throws {
        let representation = CodablePersistentKeyValueRepresentation<MigrationPayload, JSONEncoder, JSONDecoder>()

        XCTAssertThrowsError(
            try representation.decode(storageObject: Data("{}".utf8), format: .propertyList)
        ) { error in
            guard case DecodingError.keyNotFound = error else {
                return XCTFail("Expected keyNotFound, got \(error)")
            }
        }
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    func testCodableEncodePreservesUnderlyingError() {
        let representation = CodablePersistentKeyValueRepresentation<
            MigrationPayload, MigrationThrowingEncoder, JSONDecoder
        >(
            encoder: MigrationThrowingEncoder(),
            decoder: JSONDecoder()
        )

        XCTAssertThrowsError(
            try representation.encode(MigrationPayload(value: "value"), format: .propertyList)
        ) { error in
            XCTAssertEqual(error as? MigrationEncodingError, MigrationEncodingError())
        }
    }

    @available(watchOS 9.0, *)
    func testLegacyCloudURLObjectDecodes() throws {
        let representation = PrimitivePersistentKeyValueRepresentation<URL>()
        let value = URL(string: "https://example.com/legacy")!

        XCTAssertEqual(try representation.decode(storageObject: value, format: .ubiquitousKeyValueStore), value)
    }

    func testMalformedURLArchiveThrows() {
        let representation = PrimitivePersistentKeyValueRepresentation<URL>()

        XCTAssertThrowsError(try representation.decode(storageObject: Data([1, 2, 3]), format: .userDefaults))
    }

    func testNestedFailingProxyInArrayThrows() {
        let representation = PrimitivePersistentKeyValueRepresentation<[MigrationUnencodableValue]>()

        XCTAssertThrowsError(
            try representation.encode(
                [MigrationUnencodableValue(rawValue: "value")],
                format: .propertyList
            )
        )
    }

    func testNestedFailingProxyInDictionaryThrows() {
        let representation = PrimitivePersistentKeyValueRepresentation<[String: MigrationUnencodableValue]>()

        XCTAssertThrowsError(
            try representation.encode(
                ["value": MigrationUnencodableValue(rawValue: "value")],
                format: .propertyList
            )
        )
    }

    func testNestedOptionalCollectionsRoundTrip() throws {
        let representation = PrimitivePersistentKeyValueRepresentation<[[String?]]>()
        let value = [["one", nil, "three"]]
        let object = try XCTUnwrap(try representation.encode(value, format: .propertyList))
        let decoded: [[String?]] = try representation.decode(storageObject: object, format: .propertyList)

        XCTAssertEqual(decoded, [["one", "three"]])
    }

    func testOptionalNilEncodesAsRemoval() throws {
        let representation = OptionalPersistentKeyValueRepresentation(
            PrimitivePersistentKeyValueRepresentation<String>()
        )

        XCTAssertNil(try representation.encode(nil, format: .propertyList))
    }

    func testPrimitiveScalarsRoundTripAcrossFormats() throws {
        let formats: [PersistentKeyValueStorageFormat] = [
            .propertyList, .userDefaults, .ubiquitousKeyValueStore,
        ]

        for format in formats {
            let intRepresentation = PrimitivePersistentKeyValueRepresentation<Int>()
            let intObject = try XCTUnwrap(try intRepresentation.encode(42, format: format))

            XCTAssertEqual(try intRepresentation.decode(storageObject: intObject, format: format), 42)

            let dataRepresentation = PrimitivePersistentKeyValueRepresentation<Data>()
            let dataObject = try XCTUnwrap(try dataRepresentation.encode(Data([1, 2]), format: format))

            XCTAssertEqual(try dataRepresentation.decode(storageObject: dataObject, format: format), Data([1, 2]))
        }
    }

    func testURLFilePathContainingColonIsDecodedAsFilePath() throws {
        let representation = PrimitivePersistentKeyValueRepresentation<URL>()
        let value = try representation.decode(storageObject: "folder:name/file", format: .userDefaults)

        // `UserDefaults.url(forKey:)` keeps the colon unescaped, unlike `URL(fileURLWithPath:)`.
        XCTAssertTrue(value.isFileURL)
        XCTAssertEqual(value.relativeString, "folder:name/file")
        XCTAssertEqual(value.path, URL(fileURLWithPath: "folder:name/file").path)
    }

    func testURLWebValueRoundTripsThroughUserDefaultsFormat() throws {
        let value = URL(string: "https://example.com/path")!
        let representation = PrimitivePersistentKeyValueRepresentation<URL>()
        let object = try representation.encode(value, format: .userDefaults)
        let data = try XCTUnwrap(object as? Data)

        XCTAssertEqual(try representation.decode(storageObject: data, format: .userDefaults), value)
    }

    func testUnreadableProxyFailsDecode() {
        let representation = MigrationUnreadableValue.persistentKeyValueRepresentation

        XCTAssertThrowsError(try representation.decode(storageObject: "value", format: .propertyList))
    }
}
