//
//  URLUserDefaultsEncodingTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that checked `URL` encoding for `UserDefaults` refuses a file URL that the stored path cannot reproduce,
/// wherever the URL is encoded, while ordinary writes keep Foundation's behavior, and that checked decoding reads a
/// stored path as `UserDefaults.url(forKey:)` does.
final class URLUserDefaultsEncodingTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.URLUserDefaultsEncoding", function: name)
        userDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    private var fallback: URL {
        URL(string: "https://example.com/fallback")!
    }

    private var hostURL: URL {
        URL(string: "file://fileserver/shared/folder/doc")!
    }

    /// The URLs whose `UserDefaults` path loses part of their meaning: a host and a non-existent directory's trailing
    /// slash, which later relative resolution depends on, and an empty path, which `url(forKey:)` reads as `nil`.
    private var lossyURLs: [URL] {
        [
            hostURL,
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("prospective-\(UUID().uuidString)", isDirectory: true),
            URL(string: "file:")!,
        ]
    }

    /// Stored path strings that `url(forKey:)` reads as `nil`, as an empty path or one starting with or containing a
    /// null character, or reads differently from `URL(fileURLWithPath:)`, including tilde, relative, whitespace-only,
    /// colon-containing, and existing directory paths.
    private var storedPaths: [String] {
        let directory = NSTemporaryDirectory()
        let trimmedDirectory = directory.hasSuffix("/") ? String(directory.dropLast()) : directory

        return [
            "",
            "\u{0}",
            "\u{0}name",
            "folder\u{0}name",
            " ",
            "  ",
            "\n",
            "\t",
            " /tmp",
            "~",
            "~/",
            "~/folder",
            "~/folder/",
            "~\(UUID().uuidString)/folder",
            "~ /folder",
            "relative",
            "./relative",
            "../relative",
            ".",
            "..",
            "/",
            "//",
            "/tmp/./x",
            "/tmp//x",
            "a:b",
            "folder:name/file",
            "file:///tmp",
            "https://example.com",
            "%20",
            "#fragment",
            trimmedDirectory,
            trimmedDirectory + "/prospective-\(UUID().uuidString)/",
        ]
    }
}

// MARK: - Checked Decoding Tests

extension URLUserDefaultsEncodingTests {
    func test_decode_userDefaults_storedPath_matchesFoundation() throws {
        let representation = URL.persistentKeyValueRepresentation
        let key = "key:\(#function)"

        for path in storedPaths {
            userDefaults.set(path, forKey: key)

            guard let expected = userDefaults.url(forKey: key) else {
                XCTAssertThrowsError(
                    try representation.decode(storageObject: path, format: .userDefaults),
                    path.debugDescription
                ) {
                    XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue, path.debugDescription)
                }

                continue
            }

            let value = try representation.decode(storageObject: path, format: .userDefaults)

            XCTAssertEqual(value, expected, path.debugDescription)
            XCTAssertEqual(value.relativeString, expected.relativeString, path.debugDescription)
            XCTAssertEqual(value.baseURL, expected.baseURL, path.debugDescription)
        }
    }

    func test_decode_userDefaults_storedPath_followsFoundationSemantics() throws {
        let representation = URL.persistentKeyValueRepresentation
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        for path in ["", "\u{0}name", "folder\u{0}name"] {
            XCTAssertThrowsError(
                try representation.decode(storageObject: path, format: .userDefaults),
                path.debugDescription
            ) {
                XCTAssertEqual($0 as? PersistentKeyValueConversionError, .invalidStorageValue, path.debugDescription)
            }
        }

        XCTAssertEqual(
            try representation.decode(storageObject: "~", format: .userDefaults).standardizedFileURL.path,
            home.standardizedFileURL.path
        )
        XCTAssertEqual(
            try representation.decode(storageObject: "~/folder", format: .userDefaults).path,
            home.appendingPathComponent("folder").path
        )

        let blank = try representation.decode(storageObject: " ", format: .userDefaults)

        XCTAssertTrue(blank.isFileURL)
        XCTAssertEqual(blank.relativeString, "%20")
        XCTAssertEqual(blank.baseURL?.standardizedFileURL.path, workingDirectory.standardizedFileURL.path)

        let colon = try representation.decode(storageObject: "a:b", format: .userDefaults)

        XCTAssertTrue(colon.isFileURL)
        XCTAssertEqual(colon.relativeString, "a:b")
    }
}

// MARK: - Checked Encoding Tests

extension URLUserDefaultsEncodingTests {
    func test_encode_userDefaults_lossyFileURL_throws() {
        let representation = URL.persistentKeyValueRepresentation

        for url in lossyURLs {
            XCTAssertThrowsError(try representation.encode(url, format: .userDefaults), url.absoluteString) {
                XCTAssertEqual($0 as? PersistentKeyValueConversionError, .encodingFailed, url.absoluteString)
            }
        }
    }

    func test_encode_userDefaults_reproducibleFileURL_returnsPath() throws {
        let representation = URL.persistentKeyValueRepresentation
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file", isDirectory: false)
        let directory = FileManager.default.temporaryDirectory

        XCTAssertEqual(try representation.encode(file, format: .userDefaults) as? String, file.path)
        XCTAssertEqual(try representation.encode(directory, format: .userDefaults) as? String, directory.path)
    }

    func test_encode_propertyListAndUbiquitous_lossyFileURL_returnsAbsoluteString() throws {
        let representation = URL.persistentKeyValueRepresentation

        for url in lossyURLs {
            for format in [PersistentKeyValueStorageFormat.propertyList, .ubiquitousKeyValueStore] {
                XCTAssertEqual(try representation.encode(url, format: format) as? String, url.absoluteString)
            }
        }
    }
}

// MARK: - Migration Tests

extension URLUserDefaultsEncodingTests {
    func test_move_lossyFileURL_failsAtPrepareThroughEveryRepresentation() throws {
        let urlKey = PersistentKey("key:\(#function).url", defaultValue: fallback)
        let optionalKey = PersistentKey<URL?>("key:\(#function).optional", defaultValue: nil)
        let bookmarkKey = PersistentKey("key:\(#function).bookmark", defaultValue: Bookmark(url: fallback))
        let optionalBookmarkKey = PersistentKey<Bookmark?>("key:\(#function).optionalBookmark", defaultValue: nil)

        for url in lossyURLs {
            let source = InMemoryPersistentKeyValueStore()

            source.set(urlKey, to: url)
            source.set(optionalKey, to: url)
            source.set(bookmarkKey, to: Bookmark(url: url))
            source.set(optionalBookmarkKey, to: Bookmark(url: url))

            let report = try source.move(
                [urlKey, optionalKey, bookmarkKey, optionalBookmarkKey],
                to: userDefaults,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(
                report.outcomes.map(\.status),
                Array(repeating: .failed(.prepare), count: 4),
                url.absoluteString
            )
            XCTAssertEqual(
                report.outcomes.map { $0.error as? PersistentKeyValueConversionError },
                Array(repeating: .encodingFailed, count: 4),
                url.absoluteString
            )
            XCTAssertEqual(source.get(urlKey), url)
            XCTAssertEqual(source.get(optionalKey), url)
            XCTAssertEqual(source.get(bookmarkKey), Bookmark(url: url))
            XCTAssertEqual(source.get(optionalBookmarkKey), Bookmark(url: url))

            for key in [urlKey.id, optionalKey.id, bookmarkKey.id, optionalBookmarkKey.id] {
                XCTAssertNil(userDefaults.object(forKey: key), "\(key) \(url.absoluteString)")
            }
        }
    }

    func test_move_lossyFileURLsInArray_moveExactly() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: [URL]())
        let bookmarksKey = PersistentKey("key:\(#function).bookmarks", defaultValue: [Bookmark]())
        let source = InMemoryPersistentKeyValueStore()
        let urls = lossyURLs

        // Arrays store each URL as its `absoluteString`, which keeps the host and trailing slash.
        source.set(key, to: urls)
        source.set(bookmarksKey, to: urls.map(Bookmark.init))

        let report = try source.move(
            [key, bookmarksKey],
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [String], urls.map(\.absoluteString))
        XCTAssertEqual(userDefaults.get(key), urls)
        XCTAssertEqual(userDefaults.get(bookmarksKey), urls.map(Bookmark.init))
    }

    func test_move_pathThatFoundationReadsAsNil_failsAtDecodeAndKeepsSource() throws {
        let otherSuiteName = suiteName + ".other"
        let other = try XCTUnwrap(UserDefaults.migratable(suiteName: otherSuiteName))

        defer {
            other.removePersistentDomain(forName: otherSuiteName)
        }

        for (index, path) in ["", "\u{0}name", "folder\u{0}name"].enumerated() {
            for destination in [userDefaults!, other] {
                let id = "\(#function).\(index).\(destination === other)"
                let source = PersistentKey<URL?>("key:\(id).source", defaultValue: nil)
                let target = PersistentKey<URL?>("key:\(id).target", defaultValue: nil)

                userDefaults.set(path, forKey: source.id)

                XCTAssertNil(userDefaults.url(forKey: source.id), path.debugDescription)
                XCTAssertNil(userDefaults.get(source), path.debugDescription)

                let report = try userDefaults.move(
                    .key(source, to: target),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .once(id: id)
                )

                XCTAssertEqual(report.outcomes.map(\.status), [.failed(.decode)], id)
                XCTAssertEqual(
                    report.outcomes[0].error as? PersistentKeyValueConversionError,
                    .invalidStorageValue,
                    id
                )
                XCTAssertEqual(report.completion, .notRecorded, id)
                XCTAssertFalse(destination.get(.isMigrationCompleted(id: id)), id)
                XCTAssertEqual(userDefaults.object(forKey: source.id) as? String, path, id)
                XCTAssertNil(destination.object(forKey: target.id), id)
            }
        }
    }

    func test_move_pathThatFoundationReads_movesFoundationURL() throws {
        let otherSuiteName = suiteName + ".other"
        let other = try XCTUnwrap(UserDefaults.migratable(suiteName: otherSuiteName))

        defer {
            other.removePersistentDomain(forName: otherSuiteName)
        }

        for (index, path) in ["~/folder", " ", "relative", "a:b"].enumerated() {
            for destination in [userDefaults!, other] {
                let id = "\(#function).\(index).\(destination === other)"
                let source = PersistentKey<URL?>("key:\(id).source", defaultValue: nil)
                let target = PersistentKey<URL?>("key:\(id).target", defaultValue: nil)

                userDefaults.set(path, forKey: source.id)

                let expected = try XCTUnwrap(userDefaults.url(forKey: source.id), path.debugDescription)
                let report = try userDefaults.move(
                    .key(source, to: target),
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .once(id: id)
                )

                XCTAssertEqual(report.outcomes.map(\.status), [.moved], id)
                XCTAssertEqual(report.completion, .recorded, id)
                XCTAssertNil(userDefaults.object(forKey: source.id), id)
                // A relative path is stored as the absolute path it resolves to.
                XCTAssertEqual(destination.get(target)?.absoluteString, expected.absoluteString, id)
            }
        }
    }

    func test_move_reproducibleFileURL_moves() throws {
        let key = PersistentKey("key:\(#function)", defaultValue: fallback)
        let bookmarkKey = PersistentKey("key:\(#function).bookmark", defaultValue: Bookmark(url: fallback))
        let source = InMemoryPersistentKeyValueStore()
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file", isDirectory: false)

        source.set(key, to: file)
        source.set(bookmarkKey, to: Bookmark(url: file))

        let report = try source.move(
            [key, bookmarkKey],
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .moved])
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertEqual(userDefaults.get(key), file)
        XCTAssertEqual(userDefaults.get(bookmarkKey), Bookmark(url: file))
    }
}

// MARK: - Registration Tests

extension URLUserDefaultsEncodingTests {
    func test_register_lossyFileURLDefault_isNotRegistered() {
        let key = PersistentKey("key:\(#function)", defaultValue: hostURL)
        let bookmarkKey = PersistentKey("key:\(#function).bookmark", defaultValue: Bookmark(url: hostURL))
        var defaults: [String: Any] = [:]

        userDefaults.register(key, bookmarkKey)
        key.registerDefault(in: &defaults)

        XCTAssertNil(userDefaults.object(forKey: key.id))
        XCTAssertNil(userDefaults.object(forKey: bookmarkKey.id))
        XCTAssertTrue(defaults.isEmpty)
        XCTAssertEqual(userDefaults.get(key), hostURL)
        XCTAssertEqual(userDefaults.get(bookmarkKey), Bookmark(url: hostURL))
    }

    func test_register_reproducibleFileURLDefault_isRegistered() {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file", isDirectory: false)
        let key = PersistentKey("key:\(#function)", defaultValue: file)

        userDefaults.register(key)

        XCTAssertEqual(userDefaults.url(forKey: key.id), file)
        XCTAssertEqual(userDefaults.get(key), file)
    }
}

// MARK: - Ordinary Write Tests

extension URLUserDefaultsEncodingTests {
    func test_set_lossyFileURL_keepsFoundationBehavior() {
        let key = PersistentKey("key:\(#function)", defaultValue: fallback)
        let bookmarkKey = PersistentKey("key:\(#function).bookmark", defaultValue: Bookmark(url: fallback))

        userDefaults.set(key, to: hostURL)
        userDefaults.set(bookmarkKey, to: Bookmark(url: hostURL))

        XCTAssertEqual(userDefaults.get(key), URL(fileURLWithPath: "/shared/folder/doc"))
        XCTAssertEqual(userDefaults.get(bookmarkKey), Bookmark(url: URL(fileURLWithPath: "/shared/folder/doc")))
    }
}

// MARK: - Bookmark Definition

/// A value persisted through a closure proxy over `URL`.
private struct Bookmark: Equatable, KeyValuePersistible {
    let url: URL

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, URL> {
        ProxyPersistentKeyValueRepresentation(to: \.url, from: Bookmark.init(url:))
    }
}
