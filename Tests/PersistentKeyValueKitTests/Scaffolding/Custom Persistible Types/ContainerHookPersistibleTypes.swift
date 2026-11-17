//
//  ContainerHookPersistibleTypes.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit

// MARK: - Appending Token Definition

/// A value whose representation overrides the property-list array hooks the way 1.x conformers did: `set` appends to
/// the array it receives instead of assigning it.
///
/// An empty `text` fails to convert to its proxy, so a write that contains one fails.
public struct AppendingToken: Equatable, Hashable, Sendable {
    public let text: String

    // MARK: Public Initialization

    public init(_ text: String) {
        self.text = text
    }
}

// MARK: - KeyValuePersistible Extension

extension AppendingToken: KeyValuePersistible {
    // MARK: Public Static Interface

    public static var persistentKeyValueRepresentation: Representation {
        Representation()
    }
}

// MARK: - Appending Token Representation Definition

extension AppendingToken {
    /// The appending representation of ``AppendingToken``.
    public struct Representation: ProxyPersistentKeyValueRepresentationProtocol {
        // MARK: ProxyPersistentKeyValueRepresentationProtocol Implementation

        public func from(_ proxy: String) -> AppendingToken? {
            AppendingToken(proxy)
        }

        public func to(_ value: AppendingToken) -> String? {
            value.text.isEmpty ? nil : value.text
        }

        // MARK: Interfacing with Property List Array

        public func set(_ values: [AppendingToken], to propertyListArray: inout [Any]) {
            var texts: [String] = []

            for value in values {
                guard let text = to(value) else {
                    return
                }

                texts.append(text)
            }

            propertyListArray.append(contentsOf: texts)
        }
    }
}

// MARK: - Delta-Coded Tick Definition

/// A value whose representation stores an array as the differences between consecutive values.
///
/// A single value is stored as its number, but an array of `[10, 13]` is stored as `[10, 3]`, so reading or writing
/// an array element by element instead of through the array hooks produces different values.
public struct DeltaCodedTick: Equatable, Hashable, Sendable {
    public let number: Int

    // MARK: Public Initialization

    public init(_ number: Int) {
        self.number = number
    }
}

// MARK: - KeyValuePersistible Extension

extension DeltaCodedTick: KeyValuePersistible {
    // MARK: Public Static Interface

    public static var persistentKeyValueRepresentation: Representation {
        Representation()
    }
}

// MARK: - Delta-Coded Tick Representation Definition

extension DeltaCodedTick {
    /// The delta-coded representation of ``DeltaCodedTick``.
    public struct Representation: ProxyPersistentKeyValueRepresentationProtocol {
        // MARK: ProxyPersistentKeyValueRepresentationProtocol Implementation

        public func from(_ proxy: Int) -> DeltaCodedTick? {
            DeltaCodedTick(proxy)
        }

        public func to(_ value: DeltaCodedTick) -> Int? {
            value.number
        }

        // MARK: Interfacing with Property List Array

        public func get(from propertyListArray: [Any]) -> [DeltaCodedTick]? {
            guard let deltas = propertyListArray as? [Int] else {
                return nil
            }

            var total = 0

            return deltas.map { delta in
                total += delta

                return DeltaCodedTick(total)
            }
        }

        public func set(_ values: [DeltaCodedTick], to propertyListArray: inout [Any]) {
            var previous = 0

            propertyListArray = values.map { value in
                defer {
                    previous = value.number
                }

                return value.number - previous
            }
        }
    }
}
