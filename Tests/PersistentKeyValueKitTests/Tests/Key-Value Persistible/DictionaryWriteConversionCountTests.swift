//
//  DictionaryWriteConversionCountTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that an ordinary dictionary write behind built-in proxy and optional representations converts each value
/// once and stops at the first value that fails to convert.
///
/// Each value passes through every wrapping representation before the write moves on to the next value, so a value
/// whose inner conversion fails stops the write before any other value is converted.
final class DictionaryWriteConversionCountTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        (userDefaults, suiteName) = try makeStableUserDefaults("PersistentKeyValueKitTests.DictionaryWriteConversionCount", function: name)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    private let entryCount = 64

    /// Returns `entryCount` values that `make` creates as `outcome` selects, except the value that iteration visits
    /// first, which `make` creates as `firstOutcome` selects.
    private func entries<Value>(
        _ outcome: WireOutcome,
        first firstOutcome: WireOutcome,
        counts: ConversionCounts,
        make: (WireOutcome, ConversionCounts) -> Value
    ) -> [String: Value] {
        var values = Dictionary(uniqueKeysWithValues: (0 ..< entryCount).map { (String($0), make(outcome, counts)) })
        let firstKey = values.keys.first!

        values[firstKey] = make(firstOutcome, counts)

        precondition(values.keys.first == firstKey)

        return values
    }

    /// Writes `old`, then the value that `makeValue` creates, at a key of each store and container, and returns the
    /// conversion counts of the second write along with the object stored afterward.
    private func writeToEachStore<Value: KeyValuePersistible & Sendable>(
        _ makeValue: (ConversionCounts) -> [String: Value],
        old: [String: Value],
        function: String = #function
    ) -> [(store: String, counts: ConversionCounts, stored: Any?)] {
        let ubiquitousStore = MockUbiquitousKeyValueStore()
        var results: [(store: String, counts: ConversionCounts, stored: Any?)] = []

        do {
            let key = PersistentKey("key:\(function)", defaultValue: [String: Value]())
            let counts = ConversionCounts()
            let value = makeValue(counts)

            userDefaults.set(key, to: old)
            counts.reset()
            userDefaults.set(key, to: value)
            results.append(("UserDefaults", counts, userDefaults.object(forKey: key.id)))
        }

        do {
            let key = PersistentKey("key:\(function)", defaultValue: [String: Value]())
            let counts = ConversionCounts()
            let value = makeValue(counts)

            ubiquitousStore.set(key, to: old)
            counts.reset()
            ubiquitousStore.set(key, to: value)
            results.append(("NSUbiquitousKeyValueStore", counts, ubiquitousStore.object(forKey: key.id)))
        }

        do {
            var container: [String: Any] = [:]
            let counts = ConversionCounts()
            let value = makeValue(counts)

            [String: Value].set("key", to: old, in: &container)
            counts.reset()
            [String: Value].set("key", to: value, in: &container)
            results.append(("property list", counts, container["key"]))
        }

        return results
    }

    /// Asserts that each store and container keeps `["old": 27]` after writing values whose first iterated value fails
    /// as `outcome` selects, and that only that value was converted.
    private func assertFirstFailureStopsWrite<Value: KeyValuePersistible & Sendable>(
        _ outcome: WireOutcome,
        outerCalls: Int,
        innerCalls: Int,
        make: @escaping (WireOutcome, ConversionCounts) -> Value,
        file: StaticString = #filePath,
        line: UInt = #line,
        function: String = #function
    ) {
        let results = writeToEachStore(
            { entries(.encoded(42), first: outcome, counts: $0, make: make) },
            old: ["old": make(.encoded(27), ConversionCounts())],
            function: "\(function):\(outcome)"
        )

        for (store, counts, stored) in results {
            XCTAssertEqual(counts.outer, outerCalls, "\(store) \(outcome) outer", file: file, line: line)
            XCTAssertEqual(counts.inner, innerCalls, "\(store) \(outcome) inner", file: file, line: line)
            XCTAssertEqual(stored as? [String: Int], ["old": 27], "\(store) \(outcome)", file: file, line: line)
        }
    }

    /// Asserts that each store and container stores every encoded value after a write that converted each value at
    /// each layer once.
    private func assertSuccessfulWriteConvertsEachValueOnce<Value: KeyValuePersistible & Sendable>(
        outerCalls: Int,
        innerCalls: Int,
        make: @escaping (WireOutcome, ConversionCounts) -> Value,
        file: StaticString = #filePath,
        line: UInt = #line,
        function: String = #function
    ) {
        let results = writeToEachStore(
            { entries(.encoded(42), first: .omitted, counts: $0, make: make) },
            old: ["old": make(.encoded(27), ConversionCounts())],
            function: function
        )

        for (store, counts, stored) in results {
            XCTAssertEqual(counts.outer, outerCalls, "\(store) outer", file: file, line: line)
            XCTAssertEqual(counts.inner, innerCalls, "\(store) inner", file: file, line: line)
            XCTAssertEqual((stored as? [String: Int])?.count, entryCount - 1, "\(store)", file: file, line: line)
            XCTAssertEqual(Set((stored as? [String: Int] ?? [:]).values), [42], "\(store)", file: file, line: line)
        }
    }
}

// MARK: - First Failure Tests

extension DictionaryWriteConversionCountTests {
    func test_set_dictionaryOfProxiesToProxies_firstFailureStopsWrite() {
        assertFirstFailureStopsWrite(.failsInner, outerCalls: 1, innerCalls: 1, make: ProxiedWireID.init)
        assertFirstFailureStopsWrite(.failsOuter, outerCalls: 1, innerCalls: 0, make: ProxiedWireID.init)
    }

    func test_set_dictionaryOfOptionalProxiesToProxies_firstFailureStopsWrite() {
        assertFirstFailureStopsWrite(.failsInner, outerCalls: 1, innerCalls: 1) {
            Optional(ProxiedWireID($0, counts: $1))
        }
        assertFirstFailureStopsWrite(.failsOuter, outerCalls: 1, innerCalls: 0) {
            Optional(ProxiedWireID($0, counts: $1))
        }
    }

    func test_set_dictionaryOfProxiesToOptionalProxies_firstFailureStopsWrite() {
        assertFirstFailureStopsWrite(.failsInner, outerCalls: 1, innerCalls: 1, make: OptionallyProxiedWireID.init)
        assertFirstFailureStopsWrite(.failsOuter, outerCalls: 1, innerCalls: 0, make: OptionallyProxiedWireID.init)
    }

    func test_set_arrayOfDictionariesOfProxiesToProxies_firstFailureStopsWrite() {
        let key = PersistentKey("key:\(#function)", defaultValue: [[String: ProxiedWireID]]())
        let counts = ConversionCounts()
        let valid = entries(.encoded(42), first: .encoded(42), counts: counts, make: ProxiedWireID.init)
        let failing = entries(.encoded(42), first: .failsInner, counts: counts, make: ProxiedWireID.init)

        userDefaults.set(key, to: [["old": ProxiedWireID(.encoded(27), counts: ConversionCounts())]])
        userDefaults.set(key, to: [valid, failing, valid])

        XCTAssertEqual(counts.outer, entryCount + 1)
        XCTAssertEqual(counts.inner, entryCount + 1)
        XCTAssertEqual(userDefaults.array(forKey: key.id) as? [[String: Int]], [["old": 27]])
    }
}

// MARK: - Successful Write Tests

extension DictionaryWriteConversionCountTests {
    func test_set_dictionaryOfProxiesToProxies_convertsEachValueOnce() {
        let results = writeToEachStore(
            { entries(.encoded(42), first: .encoded(42), counts: $0, make: ProxiedWireID.init) },
            old: ["old": ProxiedWireID(.encoded(27), counts: ConversionCounts())]
        )

        for (store, counts, stored) in results {
            XCTAssertEqual(counts.outer, entryCount, store)
            XCTAssertEqual(counts.inner, entryCount, store)
            XCTAssertEqual((stored as? [String: Int])?.count, entryCount, store)
        }
    }

    func test_set_dictionaryOfOptionalProxiesToProxies_convertsEachValueOnce() {
        assertSuccessfulWriteConvertsEachValueOnce(outerCalls: entryCount - 1, innerCalls: entryCount - 1) {
            $0 == .omitted ? nil : ProxiedWireID($0, counts: $1)
        }
    }

    func test_set_dictionaryOfProxiesToOptionalProxies_convertsEachValueOnce() {
        assertSuccessfulWriteConvertsEachValueOnce(
            outerCalls: entryCount,
            innerCalls: entryCount - 1,
            make: OptionallyProxiedWireID.init
        )
    }
}

// MARK: - Conversion Counts Definition

/// Counts the outer and inner proxy conversions made while writing.
private final class ConversionCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var storedInner = 0
    private var storedOuter = 0

    var inner: Int {
        lock.withLock {
            storedInner
        }
    }

    var outer: Int {
        lock.withLock {
            storedOuter
        }
    }

    func recordInner() {
        lock.withLock {
            storedInner += 1
        }
    }

    func recordOuter() {
        lock.withLock {
            storedOuter += 1
        }
    }

    func reset() {
        lock.withLock {
            storedInner = 0
            storedOuter = 0
        }
    }
}

// MARK: - Wire Outcome Definition

/// How a value converts through its outer and inner proxies.
private enum WireOutcome: Equatable, CustomStringConvertible, Sendable {
    /// Both conversions succeed and the value is stored as the number.
    case encoded(Int)

    /// The inner conversion fails.
    case failsInner

    /// The outer conversion fails.
    case failsOuter

    /// The value is omitted where its representation can omit it.
    case omitted

    var description: String {
        switch self {
        case let .encoded(number):
            "encoded(\(number))"
        case .failsInner:
            "failsInner"
        case .failsOuter:
            "failsOuter"
        case .omitted:
            "omitted"
        }
    }
}

// MARK: - Wire ID Definition

/// A number stored through a built-in proxy to `Int`, whose conversion counts as the inner conversion and fails for a
/// negative number.
private struct WireID: KeyValuePersistible, Sendable {
    let counts: ConversionCounts
    let number: Int

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, Int> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.counts.recordInner()

                return $0.number < 0 ? nil : $0.number
            },
            from: {
                WireID(counts: ConversionCounts(), number: $0)
            }
        )
    }
}

// MARK: - Proxied Wire ID Definition

/// A value stored through a built-in proxy to ``WireID``, whose conversion counts as the outer conversion.
///
/// The outer conversion fails for ``WireOutcome/failsOuter``. A value that would be omitted stores `0`, because neither
/// proxy can omit a value.
private struct ProxiedWireID: KeyValuePersistible, Sendable {
    let counts: ConversionCounts
    let outcome: WireOutcome

    init(_ outcome: WireOutcome, counts: ConversionCounts) {
        self.counts = counts
        self.outcome = outcome
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, WireID> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.counts.recordOuter()

                return switch $0.outcome {
                case let .encoded(number):
                    WireID(counts: $0.counts, number: number)
                case .failsInner:
                    WireID(counts: $0.counts, number: -1)
                case .failsOuter:
                    nil
                case .omitted:
                    WireID(counts: $0.counts, number: 0)
                }
            },
            from: {
                ProxiedWireID(.encoded($0.number), counts: ConversionCounts())
            }
        )
    }
}

// MARK: - Optionally Proxied Wire ID Definition

/// A value stored through a built-in proxy to an optional ``WireID``, whose conversion counts as the outer conversion.
///
/// The outer conversion fails for ``WireOutcome/failsOuter`` and returns a `nil` proxy, which omits the value, for
/// ``WireOutcome/omitted``.
private struct OptionallyProxiedWireID: KeyValuePersistible, Sendable {
    let counts: ConversionCounts
    let outcome: WireOutcome

    init(_ outcome: WireOutcome, counts: ConversionCounts) {
        self.counts = counts
        self.outcome = outcome
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, WireID?> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.counts.recordOuter()

                return switch $0.outcome {
                case let .encoded(number):
                    .some(WireID(counts: $0.counts, number: number))
                case .failsInner:
                    .some(WireID(counts: $0.counts, number: -1))
                case .failsOuter:
                    nil
                case .omitted:
                    .some(nil)
                }
            },
            from: {
                OptionallyProxiedWireID(($0?.number).map(WireOutcome.encoded) ?? .omitted, counts: ConversionCounts())
            }
        )
    }
}
