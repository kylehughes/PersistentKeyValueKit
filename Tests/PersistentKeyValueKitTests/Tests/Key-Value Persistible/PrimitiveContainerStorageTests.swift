//
//  PrimitiveContainerStorageTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Pins the property-list objects that built-in primitives write into arrays and dictionaries, byte for byte.
///
/// Binary property lists preserve the storage type of each scalar (for example, `Float` versus `Double`), so equal
/// bytes mean equal storage. Dictionaries hold one entry each because binary key order is not specified.
final class PrimitiveContainerStorageTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.PrimitiveContainerStorage", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Tests

    func test_array() throws {
        try assertStorage([[1, 2], [], [3]] as [[Int]], expected: [[1, 2], [], [3]])
        try assertStorage([["a", "b"]] as [[String]], expected: [["a", "b"]])
    }

    func test_bool() throws {
        try assertStorage([true, false], expected: [true, false])
    }

    func test_data() throws {
        try assertStorage([Data([0, 1, 2]), Data()], expected: [Data([0, 1, 2]), Data()])
    }

    func test_dictionary() throws {
        try assertStorage([["a": 1], [:]] as [[String: Int]], expected: [["a": 1], [String: Any]()])
        try assertStorage([["b": "c"]] as [[String: String]], expected: [["b": "c"]])
    }

    func test_double() throws {
        try assertStorage(
            [1.5, -0.25, .greatestFiniteMagnitude],
            expected: [1.5, -0.25, Double.greatestFiniteMagnitude]
        )
    }

    func test_float() throws {
        try assertStorage([Float(1.5), Float(-0.25)], expected: [Float(1.5), Float(-0.25)])
    }

    func test_int() throws {
        try assertStorage([0, .max, .min], expected: [0, Int.max, Int.min])
    }

    func test_string() throws {
        try assertStorage(["", "value", "ünïcødé"], expected: ["", "value", "ünïcødé"])
    }

    func test_url() throws {
        let urls = [
            try XCTUnwrap(URL(string: "https://example.com/path?query=1")),
            URL(fileURLWithPath: "/tmp/file.txt"),
        ]

        try assertStorage(urls, expected: ["https://example.com/path?query=1", "file:///tmp/file.txt"])
    }

    // MARK: Private Instance Interface

    private func assertStorage<Value>(
        _ values: [Value],
        expected: [Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws where Value: Equatable & KeyValuePersistible & Sendable {
        let representation = Value.persistentKeyValueRepresentation
        let expectedArray = try binaryPropertyList(expected)

        var array: [Any] = []
        representation.set(values, to: &array)

        XCTAssertEqual(try binaryPropertyList(array), expectedArray, "array", file: file, line: line)
        XCTAssertEqual(representation.get(from: array), values, "array round trip", file: file, line: line)

        var nonEmptyArray: [Any] = ["stale"]
        representation.set(values, to: &nonEmptyArray)

        XCTAssertEqual(try binaryPropertyList(nonEmptyArray), expectedArray, "array assignment", file: file, line: line)

        for (value, expectedObject) in zip(values, expected) {
            var dictionary: [String: Any] = [:]
            representation.set("key", to: value, in: &dictionary)

            XCTAssertEqual(
                try binaryPropertyList(dictionary),
                try binaryPropertyList(["key": expectedObject]),
                "dictionary",
                file: file,
                line: line
            )
            XCTAssertEqual(
                representation.get("key", from: dictionary),
                value,
                "dictionary round trip",
                file: file,
                line: line
            )

            let dictionaryKey = PersistentKey("dictionary", defaultValue: [String: Value]())
            userDefaults.set(dictionaryKey, to: ["key": value])

            XCTAssertEqual(
                try binaryPropertyList(XCTUnwrap(userDefaults.object(forKey: dictionaryKey.id))),
                try binaryPropertyList(["key": expectedObject]),
                "UserDefaults dictionary",
                file: file,
                line: line
            )
            XCTAssertEqual(userDefaults.get(dictionaryKey), ["key": value], file: file, line: line)
        }

        let arrayKey = PersistentKey("array", defaultValue: [Value]())
        userDefaults.set(arrayKey, to: values)

        XCTAssertEqual(
            try binaryPropertyList(XCTUnwrap(userDefaults.object(forKey: arrayKey.id))),
            expectedArray,
            "UserDefaults array",
            file: file,
            line: line
        )
        XCTAssertEqual(userDefaults.get(arrayKey), values, "UserDefaults array round trip", file: file, line: line)
    }

    private func binaryPropertyList(_ object: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }
}
