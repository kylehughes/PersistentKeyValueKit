//
//  RecursiveContainerWriteTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// Verifies that writing a recursive custom value invokes each encoding hook once, whether the write succeeds or fails.
///
/// ``RecursiveNode`` encodes its child through a package container, the way a tree-shaped custom type would. A
/// container write that retries a failed child re-encodes that child's whole subtree, so retrying at every level takes
/// time exponential in the depth of the tree.
final class RecursiveContainerWriteTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("PersistentKeyValueKitTests.RecursiveContainerWrite", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Private Instance Interface

    private let depth = 12

    /// Returns a chain of `depth` branches, each nesting its child with `nesting`, that ends in a valid or invalid leaf.
    private func tree(
        nesting: RecursiveNode.Nesting,
        isValid: Bool,
        counter: HookCallCounter
    ) -> RecursiveNode {
        var node = RecursiveNode(isValid ? .leaf(7) : .invalid, counter: counter)

        for _ in 0 ..< depth {
            node = RecursiveNode(.branch(node, nesting), counter: counter)
        }

        return node
    }

    /// The number of hook calls that encoding the tree once takes: one `encode` per node, plus one conversion per
    /// proxy layer around each nested child.
    private func expectedHookCalls(for nesting: RecursiveNode.Nesting) -> Int {
        let hooksPerLevel = switch nesting {
        case .doublyProxiedArray:
            3
        case .proxyArray:
            2
        case .array, .arrayOfArrays, .dictionary, .optionalArray, .optionalDictionary:
            1
        }

        return depth * hooksPerLevel + 1
    }
}

// MARK: - Ordinary Write Tests

extension RecursiveContainerWriteTests {
    func test_set_validRecursiveValue_invokesEachHookOnce() {
        for nesting in RecursiveNode.Nesting.allCases {
            let counter = HookCallCounter()
            let key = PersistentKey("key:\(#function):\(nesting)", defaultValue: [RecursiveNode]())

            userDefaults.set(key, to: [tree(nesting: nesting, isValid: true, counter: counter)])

            XCTAssertEqual(counter.count, expectedHookCalls(for: nesting), "\(nesting)")
            XCTAssertNotNil(userDefaults.array(forKey: key.id)?.first as? [String: Any], "\(nesting)")
        }
    }

    func test_set_failedRecursiveValue_invokesEachHookOnceAndLeavesStoredValue() {
        for nesting in RecursiveNode.Nesting.allCases {
            let counter = HookCallCounter()
            let key = PersistentKey("key:\(#function):\(nesting)", defaultValue: [RecursiveNode]())

            userDefaults.set(key, to: [RecursiveNode(.leaf(99), counter: counter)])
            counter.reset()

            userDefaults.set(key, to: [tree(nesting: nesting, isValid: false, counter: counter)])

            XCTAssertEqual(counter.count, expectedHookCalls(for: nesting), "\(nesting)")
            XCTAssertEqual(userDefaults.array(forKey: key.id) as? [Int], [99], "\(nesting)")
        }
    }

    func test_set_failedRecursiveDictionaryValue_invokesEachHookOnceAndLeavesStoredValue() {
        for nesting in RecursiveNode.Nesting.allCases {
            let counter = HookCallCounter()
            let key = PersistentKey("key:\(#function):\(nesting)", defaultValue: [String: RecursiveNode]())

            userDefaults.set(key, to: ["root": RecursiveNode(.leaf(99), counter: counter)])
            counter.reset()

            userDefaults.set(key, to: ["root": tree(nesting: nesting, isValid: false, counter: counter)])

            XCTAssertEqual(counter.count, expectedHookCalls(for: nesting), "\(nesting)")
            XCTAssertEqual(userDefaults.dictionary(forKey: key.id) as? [String: Int], ["root": 99], "\(nesting)")
        }
    }
}

// MARK: - Checked Conversion Tests

extension RecursiveContainerWriteTests {
    func test_checkedEncode_recursiveValue_invokesEachHookOnce() throws {
        let representation = [RecursiveNode].persistentKeyValueRepresentation

        for nesting in RecursiveNode.Nesting.allCases {
            let counter = HookCallCounter()

            let encoded = try representation.encode(
                [tree(nesting: nesting, isValid: true, counter: counter)],
                format: .propertyList
            )

            XCTAssertNotNil((encoded as? [Any])?.first as? [String: Any], "\(nesting)")
            XCTAssertEqual(counter.count, expectedHookCalls(for: nesting), "\(nesting)")

            counter.reset()

            XCTAssertThrowsError(
                try representation.encode(
                    [tree(nesting: nesting, isValid: false, counter: counter)],
                    format: .propertyList
                ),
                "\(nesting)"
            )
            XCTAssertEqual(counter.count, expectedHookCalls(for: nesting), "\(nesting)")
        }
    }
}

// MARK: - Hook Call Counter Definition

/// Counts the encoding hook calls made while writing a ``RecursiveNode`` tree.
private final class HookCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storedCount
    }

    func record() {
        lock.lock()
        defer {
            lock.unlock()
        }

        storedCount += 1
    }

    func reset() {
        lock.lock()
        defer {
            lock.unlock()
        }

        storedCount = 0
    }
}

// MARK: - Recursive Node Definition

/// A tree node whose custom representation encodes its child through a package container.
///
/// An invalid leaf fails to encode, which fails every enclosing branch.
private struct RecursiveNode: KeyValuePersistible, Sendable {
    /// The container that a branch stores its child in.
    enum Nesting: CaseIterable, Sendable {
        case array
        case arrayOfArrays
        case dictionary
        case doublyProxiedArray
        case optionalArray
        case optionalDictionary
        case proxyArray
    }

    indirect enum Content: Sendable {
        case branch(RecursiveNode, Nesting)
        case invalid
        case leaf(Int)
    }

    let content: Content
    let counter: HookCallCounter

    init(_ content: Content, counter: HookCallCounter) {
        self.content = content
        self.counter = counter
    }

    static var persistentKeyValueRepresentation: RecursiveNodeRepresentation {
        RecursiveNodeRepresentation()
    }
}

/// The representation of ``RecursiveNode``, which counts its `encode` calls.
private struct RecursiveNodeRepresentation: PersistentKeyValueRepresentation {
    // MARK: PersistentKeyValueRepresentation Implementation

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> RecursiveNode {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }

    func encode(_ value: RecursiveNode, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value.counter.record()

        switch value.content {
        case let .branch(child, nesting):
            var fields: [String: Any] = [:]

            switch nesting {
            case .array:
                [RecursiveNode].set("children", to: [child], in: &fields)
            case .arrayOfArrays:
                [[RecursiveNode]].set("children", to: [[child]], in: &fields)
            case .dictionary:
                [String: RecursiveNode].set("children", to: ["child": child], in: &fields)
            case .doublyProxiedArray:
                [DoublyProxiedRecursiveNode].set(
                    "children",
                    to: [DoublyProxiedRecursiveNode(ProxiedRecursiveNode(child))],
                    in: &fields
                )
            case .optionalArray:
                [RecursiveNode?].set("children", to: [child], in: &fields)
            case .optionalDictionary:
                [String: RecursiveNode?].set("children", to: ["child": child], in: &fields)
            case .proxyArray:
                [ProxiedRecursiveNode].set("children", to: [ProxiedRecursiveNode(child)], in: &fields)
            }

            guard fields["children"] != nil else {
                throw PersistentKeyValueConversionError.encodingFailed
            }

            return fields
        case .invalid:
            throw PersistentKeyValueConversionError.encodingFailed
        case let .leaf(number):
            return number
        }
    }
}

// MARK: - Proxied Recursive Node Definition

/// A ``RecursiveNode`` stored through a built-in proxy representation, which counts its proxy conversions.
private struct ProxiedRecursiveNode: KeyValuePersistible, Sendable {
    let node: RecursiveNode

    init(_ node: RecursiveNode) {
        self.node = node
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, RecursiveNode> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.node.counter.record()

                return $0.node
            },
            from: {
                ProxiedRecursiveNode($0)
            }
        )
    }
}

/// A ``ProxiedRecursiveNode`` stored through another built-in proxy representation, which counts its proxy
/// conversions.
private struct DoublyProxiedRecursiveNode: KeyValuePersistible, Sendable {
    let proxied: ProxiedRecursiveNode

    init(_ proxied: ProxiedRecursiveNode) {
        self.proxied = proxied
    }

    static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, ProxiedRecursiveNode> {
        ProxyPersistentKeyValueRepresentation(
            to: {
                $0.proxied.node.counter.record()

                return $0.proxied
            },
            from: {
                DoublyProxiedRecursiveNode($0)
            }
        )
    }
}
