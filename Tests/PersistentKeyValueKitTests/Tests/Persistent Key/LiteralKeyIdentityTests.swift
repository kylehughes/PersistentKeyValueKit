//
//  LiteralKeyIdentityTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that key identity matches Foundation's literal key identity, equal UTF-16 code units, for every way an
/// identifier can be stored.
///
/// A Swift string stores its contents natively as UTF-8 or, when bridged from an `NSString`, in that object. Identifiers
/// are compared by different means depending on that storage, so every pair of storage forms must agree: equal exactly
/// when the code units are equal, including unpaired surrogates, U+FFFD, embedded NUL, and canonically equivalent
/// spellings, and hashing equally when equal.
final class LiteralKeyIdentityTests: XCTestCase {
    // MARK: Private Static Interface

    /// Stems of lengths that cover small, tagged, and heap-allocated strings, and the long shared prefixes that put a
    /// mismatch at the end of, or just beyond, a comparison's chunk.
    ///
    /// Tests that need only a short and a long stem use the stems at indexes 1 and 8.
    private static let stems: [[UInt16]] = [0, 1, 4, 12, 14, 15, 16, 23, 65, 128, 8, 31, 32, 63, 64, 127, 256, 513].map {
        Array(repeating: 0x61, count: $0)
    }

    /// The code units that follow each stem: unpaired surrogates, U+FFFD, canonically equivalent spellings, and
    /// controls that differ in ASCII.
    private static let suffixes: [[UInt16]] = [
        [0xD800], [0xD83E], [0xDBFF], [0xDC00], [0xDFFF], [0xFFFD],
        [0xD800, 0xDC00], [0xD800, 0xDBFF], [0xDFFF, 0xDFFF], [0xDFFF, 0x61], [0xD800, 0x61], [0xFFFD, 0x61],
        [0xE9], [0x65, 0x301], [0x212A], [0x4B], [0x61, 0, 0x62], [0x61], [0x41],
        [], [0], [0, 0x61], [0x61, 0], [0x0D], [0x0A], [0x0D, 0x0A], [0x200B], [0xFE0F], [0xFEFF], [0xFFFF], [0xFFFE],
        [0xFDD0], [0xAD], [0x65, 0x301, 0x327], [0x65, 0x327, 0x301], [0xDFFF, 0xD800], [0xD83D, 0xDE01],
        [0xD83D, 0xDE02], [0xD83D, 0xDE01, 0xFE0F],
    ]

    /// Returns `codeUnits` in each storage form that can hold it: bridged from a Core Foundation string, bridged from
    /// an `NSString` subclass, which Swift bridges lazily, and, when it is valid Unicode, native.
    private static func forms(of codeUnits: [UInt16]) -> [String] {
        let bridged = NSString(characters: codeUnits, length: codeUnits.count) as String
        var forms = [bridged, AccessObservingString.make(bridged) as String]

        // Decoding replaces each unpaired surrogate with U+FFFD, so only valid Unicode decodes to the same code units.
        let native = String(decoding: codeUnits, as: UTF16.self)
        if native.utf16.elementsEqual(codeUnits) {
            forms.append(native)
        }

        return forms
    }

    /// Returns every identifier made from `stem` and ``suffixes``, in each storage form that can hold it.
    ///
    /// Identifiers that are valid Unicode also appear as native Swift strings. Every identifier appears bridged from a
    /// Core Foundation string and from an `NSString` subclass, which Swift bridges lazily.
    private static func identifiers(stem: [UInt16]) -> [(id: String, codeUnits: [UInt16])] {
        suffixes.flatMap { suffix in
            let codeUnits = stem + suffix

            return forms(of: codeUnits).map {
                ($0, codeUnits)
            }
        }
    }
}

// MARK: - Key Identity Tests

extension LiteralKeyIdentityTests {
    // MARK: Tests

    func test_persistentKey_equatableAndHashable_matchLiteralCodeUnits() {
        var checkCount = 0

        for stem in Self.stems {
            let identifiers = Self.identifiers(stem: stem)
            let keys = identifiers.map {
                PersistentKey($0.id, defaultValue: 0)
            }

            for (lhs, lhsKey) in zip(identifiers, keys) {
                for (rhs, rhsKey) in zip(identifiers, keys) {
                    let isLiterallyEqual = lhs.codeUnits == rhs.codeUnits

                    XCTAssertEqual(lhsKey == rhsKey, isLiterallyEqual, "\(lhs.codeUnits) \(rhs.codeUnits)")

                    if isLiterallyEqual {
                        XCTAssertEqual(lhsKey.hashValue, rhsKey.hashValue, "\(lhs.codeUnits)")
                    }

                    checkCount += 1
                }
            }

            XCTAssertEqual(Set(keys).count, Set(identifiers.map(\.codeUnits)).count)
        }

        XCTAssertGreaterThanOrEqual(checkCount, 190_000)
    }

    func test_persistentDebugKey_equatableAndHashable_matchLiteralCodeUnits() {
        for stem in Self.stems {
            let identifiers = Self.identifiers(stem: stem)
            let keys = identifiers.map {
                PersistentDebugKey($0.id, defaultValue: 0)
            }

            for (lhs, lhsKey) in zip(identifiers, keys) {
                for (rhs, rhsKey) in zip(identifiers, keys) {
                    let isLiterallyEqual = lhs.codeUnits == rhs.codeUnits

                    XCTAssertEqual(lhsKey == rhsKey, isLiterallyEqual, "\(lhs.codeUnits) \(rhs.codeUnits)")

                    if isLiterallyEqual {
                        XCTAssertEqual(lhsKey.hashValue, rhsKey.hashValue, "\(lhs.codeUnits)")
                    }
                }
            }

            XCTAssertEqual(Set(keys).count, Set(identifiers.map(\.codeUnits)).count)
        }
    }
}

// MARK: - Random Identifier Tests

extension LiteralKeyIdentityTests {
    // MARK: Tests

    func test_persistentKeyAndDebugKey_equatableAndHashable_matchLiteralCodeUnitsForRandomIdentifiers() {
        var generator = SplitMix64Generator(seed: 0x901E_F947_C9D6_92C3)
        var crossStorageEqualCount = 0

        for _ in 0 ..< 1_024 {
            let codeUnits = (0 ..< Int.random(in: 0 ... 84, using: &generator)).map { _ in
                UInt16.random(in: .min ... .max, using: &generator)
            }
            var variant = codeUnits

            if variant.isEmpty {
                variant.append(0)
            } else {
                variant[Int.random(in: 0 ..< variant.count, using: &generator)] ^= 1
            }

            for other in [codeUnits, variant] {
                let isLiterallyEqual = codeUnits == other

                for lhs in Self.forms(of: codeUnits) {
                    for rhs in Self.forms(of: other) {
                        let lhsKey = PersistentKey(lhs, defaultValue: 0)
                        let rhsKey = PersistentKey(rhs, defaultValue: 0)
                        let lhsDebugKey = PersistentDebugKey(lhs, defaultValue: 0)
                        let rhsDebugKey = PersistentDebugKey(rhs, defaultValue: 0)

                        XCTAssertEqual(lhsKey == rhsKey, isLiterallyEqual, "\(codeUnits) \(other)")
                        XCTAssertEqual(rhsKey == lhsKey, isLiterallyEqual, "\(codeUnits) \(other)")
                        XCTAssertEqual(lhsDebugKey == rhsDebugKey, isLiterallyEqual, "\(codeUnits) \(other)")
                        XCTAssertEqual(rhsDebugKey == lhsDebugKey, isLiterallyEqual, "\(codeUnits) \(other)")

                        if isLiterallyEqual {
                            XCTAssertEqual(lhsKey.hashValue, rhsKey.hashValue, "\(codeUnits)")
                            XCTAssertEqual(lhsDebugKey.hashValue, rhsDebugKey.hashValue, "\(codeUnits)")

                            if lhs.isContiguousUTF8 != rhs.isContiguousUTF8 {
                                crossStorageEqualCount += 1
                            }
                        }
                    }
                }
            }
        }

        XCTAssertGreaterThan(crossStorageEqualCount, 0)
    }
}

// MARK: - Migration Report Tests

extension LiteralKeyIdentityTests {
    // MARK: Tests

    func test_outcome_matchesLiteralCodeUnits() {
        for stem in [Self.stems[1], Self.stems[8]] {
            let identifiers = Self.identifiers(stem: stem)

            for (index, outcomeIdentifier) in identifiers.enumerated() {
                let report = PersistentKeyMigrationReport(
                    outcomes: [PersistentKeyMigrationReport.Outcome(sourceKeyID: outcomeIdentifier.id, status: .copied)],
                    completion: .untracked
                )

                for identifier in identifiers {
                    XCTAssertEqual(
                        report.outcome(for: PersistentKey(identifier.id, defaultValue: 0)) != nil,
                        identifier.codeUnits == outcomeIdentifier.codeUnits,
                        "\(index) \(identifier.codeUnits)"
                    )
                }
            }
        }
    }
}

// MARK: - Observation Tests

@available(watchOS 9.0, *)
extension LiteralKeyIdentityTests {
    // MARK: Tests

    func test_ubiquitousStoreRegister_notifiesObserversWhoseKeyMatchesLiteralCodeUnits() {
        let store = MockUbiquitousKeyValueStore()

        for stem in [Self.stems[1], Self.stems[8]] {
            let identifiers = Self.identifiers(stem: stem)
            let keys = identifiers.map {
                PersistentKey($0.id, defaultValue: 0)
            }
            let observers = keys.map { _ in
                RecordingKeyObserver()
            }

            for (key, observer) in zip(keys, observers) {
                store.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
            }

            for changed in identifiers {
                let counts = observers.map(\.notifications.count)

                NotificationCenter.default.post(
                    name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                    object: store,
                    userInfo: [
                        NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
                        NSUbiquitousKeyValueStoreChangedKeysKey: [changed.id],
                    ]
                )

                XCTAssertEqual(
                    zip(observers, counts).map { $0.notifications.count - $1 },
                    identifiers.map { $0.codeUnits == changed.codeUnits ? 1 : 0 },
                    "\(changed.codeUnits)"
                )
            }

            for (key, observer) in zip(keys, observers) {
                store.deregister(observer, for: key, context: nil)
            }
        }
    }
}

// MARK: - SplitMix64Generator Definition

/// A deterministic random number generator, so that a failing identifier reproduces.
private struct SplitMix64Generator: RandomNumberGenerator {
    private var state: UInt64

    // MARK: Internal Initialization

    init(seed: UInt64) {
        state = seed
    }

    // MARK: RandomNumberGenerator Implementation

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15

        var value = state

        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB

        return value ^ (value >> 31)
    }
}
