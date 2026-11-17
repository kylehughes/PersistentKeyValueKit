//
//  ConversionOnlyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit

/// A failure thrown by the conversion-only scaffolding when asked to encode a negative value.
public struct ConversionOnlyEncodingFailure: Error {
}

/// A representation that implements only the conversion requirements, so every store-specific method uses the
/// protocol's default implementation.
///
/// Values are stored as `Int` objects. Encoding a negative value throws, encoding `0` returns `nil` (remove), and
/// decoding anything other than an `Int` throws.
public struct ConversionOnlyPersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    public typealias Value = ConversionOnlyValue

    // MARK: Public Initialization

    public init() {}

    // MARK: PersistentKeyValueRepresentation Implementation

    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        guard let rawValue = storageObject as? Int else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return Value(rawValue)
    }

    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        if value.rawValue < 0 {
            throw ConversionOnlyEncodingFailure()
        }

        return value.rawValue == 0 ? nil : value.rawValue
    }
}

/// A value whose representation is ``ConversionOnlyPersistentKeyValueRepresentation``.
public struct ConversionOnlyValue: Equatable, Hashable, KeyValuePersistible, Sendable {
    public let rawValue: Int

    // MARK: Public Initialization

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: KeyValuePersistible Implementation

    public static var persistentKeyValueRepresentation: ConversionOnlyPersistentKeyValueRepresentation {
        ConversionOnlyPersistentKeyValueRepresentation()
    }
}

/// A primitive that implements only the conversion requirements, so its `UserDefaults` and
/// `NSUbiquitousKeyValueStore` methods use the protocol's default implementations.
///
/// Values are stored as `Int` objects with the same rules as ``ConversionOnlyPersistentKeyValueRepresentation``.
public struct ConversionOnlyPrimitive: Equatable, PrimitiveKeyValuePersistible, Sendable {
    public let rawValue: Int

    // MARK: Public Initialization

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: KeyValuePersistible Implementation

    public static var persistentKeyValueRepresentation: PrimitivePersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }

    // MARK: PrimitiveKeyValuePersistible Implementation

    public static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self {
        guard let rawValue = storageObject as? Int else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return Self(rawValue)
    }

    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        if rawValue < 0 {
            throw ConversionOnlyEncodingFailure()
        }

        return rawValue == 0 ? nil : rawValue
    }
}
