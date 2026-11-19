//
//  UnpairedSurrogateKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that identifiers that differ only in unpaired UTF-16 surrogates stay distinct where Foundation keeps them
/// distinct.
///
/// An identifier bridged from an `NSString` can contain an unpaired surrogate, such as one truncated in the middle of an
/// emoji. Swift's `utf16` view reports U+FFFD for it, so such identifiers read the same code units as each other and as
/// a native identifier ending in U+FFFD, while a `UserDefaults` suite stores a separate value under each.
final class UnpairedSurrogateKeyTests: XCTestCase {
    private var otherSuiteName: String!
    private var otherUserDefaults: UserDefaults!
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.UnpairedSurrogateKey", function: name)
        otherSuiteName = stableSuiteName("PersistentKeyValueKitTests.UnpairedSurrogateKey.Other", function: name)
        userDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        otherUserDefaults = try XCTUnwrap(UserDefaults.migratable(suiteName: otherSuiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        otherUserDefaults.removePersistentDomain(forName: otherSuiteName)
        otherUserDefaults = nil
        otherSuiteName = nil
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    /// Returns keys for the identifiers from ``unpairedSurrogateKeyIDs(_:)``, which contain a period so that
    /// `UserDefaults` observation cannot use key-value observation.
    private func keys(_ function: String = #function) -> [PersistentKey<Int>] {
        unpairedSurrogateKeyIDs("key.\(function).").map {
            PersistentKey($0, defaultValue: -1)
        }
    }
}

// MARK: - Store Tests

extension UnpairedSurrogateKeyTests {
    // MARK: Tests

    func test_set_storesEachIdentifierSeparately() {
        let keys = keys()

        XCTAssertEqual(Set(keys.map { Array($0.id.utf16) }).count, 1, "Swift must report the same code units.")

        for (index, key) in keys.enumerated() {
            userDefaults.set(key, to: 10 + index)
        }

        XCTAssertEqual(keys.map { userDefaults.get($0) }, [10, 11, 12])
    }
}

// MARK: - Observation Tests

extension UnpairedSurrogateKeyTests {
    // MARK: Tests

    func test_register_observesEachKeyIndependently() {
        let keys = keys()
        let observers = keys.map { _ in
            RecordingKeyObserver()
        }

        for (key, observer) in zip(keys, observers) {
            userDefaults.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        for (index, key) in keys.enumerated() {
            userDefaults.set(key, to: 10 + index)

            XCTAssertEqual(observers.map(\.observations.count), keys.indices.map { $0 <= index ? 1 : 0 }, "\(index)")
        }

        for (key, observer) in zip(keys, observers) {
            userDefaults.deregister(observer, for: key, context: nil)
        }
    }

    func test_deregister_removesOnlyRequestedKey() {
        let keys = keys()
        let observer = RecordingKeyObserver()

        for key in keys {
            userDefaults.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        userDefaults.deregister(observer, for: keys[0], context: nil)
        userDefaults.set(keys[0], to: 10)

        XCTAssertTrue(observer.observations.isEmpty)

        userDefaults.set(keys[1], to: 11)
        userDefaults.set(keys[2], to: 12)

        XCTAssertEqual(observer.observations.count, 2)

        userDefaults.deregister(observer, for: keys[1], context: nil)
        userDefaults.deregister(observer, for: keys[2], context: nil)
    }
}

// MARK: - Migration Tests

extension UnpairedSurrogateKeyTests {
    // MARK: Tests

    func test_copy_sameSuiteBetweenKeys_copiesValue() throws {
        let keys = keys()

        userDefaults.set(keys[0], to: 10)

        let report = try userDefaults.copy(
            .key(keys[0], to: keys[1]),
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.copied])
        XCTAssertEqual(keys.map { userDefaults.get($0) }, [10, 10, -1])
    }

    func test_move_sameSuiteBetweenKeys_movesValue() throws {
        let keys = keys()

        userDefaults.set(keys[0], to: 10)
        userDefaults.set(keys[1], to: 11)

        let report = try userDefaults.move(
            .key(keys[0], to: keys[2]),
            to: userDefaults,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(keys.map { userDefaults.get($0) }, [-1, 11, 10])
    }

    func test_copy_crossSuiteBatch_copiesEachKey() throws {
        let keys = keys()

        for (index, key) in keys.enumerated() {
            userDefaults.set(key, to: 10 + index)
        }

        let report = try userDefaults.copy(keys, to: otherUserDefaults, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.copied, .copied, .copied])
        XCTAssertEqual(keys.map { otherUserDefaults.get($0) }, [10, 11, 12])
    }

    func test_outcome_matchesOnlyRequestedKey() throws {
        let keys = keys()

        userDefaults.set(keys[0], to: 10)

        let report = try userDefaults.copy(keys[0], to: otherUserDefaults, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(keys.map { report.outcome(for: $0)?.status }, [.copied, nil, nil])
        XCTAssertEqual(keys.map { otherUserDefaults.get($0) }, [10, -1, -1])
    }
}

// MARK: - Key Identity Tests

extension UnpairedSurrogateKeyTests {
    // MARK: Tests

    func test_persistentKey_equatableAndHashable_keepEachIdentifierSeparate() {
        let keys = keys()
        // Separate `NSString` objects with the same code units, including one for the native identifier.
        let copies = keys.map { key in
            let string = key.id as NSString
            var codeUnits = [unichar](repeating: 0, count: string.length)

            string.getCharacters(&codeUnits, range: NSRange(location: 0, length: codeUnits.count))

            return PersistentKey(NSString(characters: codeUnits, length: codeUnits.count) as String, defaultValue: -1)
        }

        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(Set(keys + copies).count, 3)
        XCTAssertEqual(keys.map { $0 == keys[0] }, [true, false, false])
        XCTAssertEqual(keys.map { $0 == keys[2] }, [false, false, true])
        XCTAssertEqual(keys, copies)
        XCTAssertEqual(keys.map(\.hashValue), copies.map(\.hashValue))
    }

    func test_persistentDebugKey_equatableAndHashable_keepEachIdentifierSeparate() {
        let keys = keys().map {
            PersistentDebugKey($0.id, defaultValue: -1)
        }

        XCTAssertEqual(Set(keys).count, 3)
        XCTAssertEqual(keys.map { $0 == keys[1] }, [false, true, false])
    }
}
