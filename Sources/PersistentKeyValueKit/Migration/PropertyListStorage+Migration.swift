//
//  PropertyListStorage+Migration.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation

// MARK: - Migration Extension

extension PropertyListStorage {
    // MARK: Internal Static Interface

    static func byteCount(_ object: Any) throws -> Int {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).count
    }

    /// Returns `object` normalized through a binary property list, as a Foundation store persists it.
    static func freeze(_ object: Any) throws -> Any {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    /// Returns ``exactCopy(_:)`` of an encoded object, throwing
    /// ``PersistentKeyValueConversionError/encodingFailed`` when the property list a Foundation store persists would
    /// differ from it as ``equal(_:_:)`` compares them.
    ///
    /// A migration write commits the copy, as an ordinary `set` writes the encoded object, so a read in the same
    /// process returns what the representation encoded. A serialized property list stores an `NSDecimalNumber` as a
    /// double-precision real, which can round an integer or change how a representation decodes it, so a migration
    /// write of such an object fails before anything is written. An integer's width is not part of its stored value,
    /// so a write of an `Int32` does not fail even though other processes read it as a 64-bit integer.
    static func storableCopy(of object: Any) throws -> Any {
        let copy = try exactCopy(object)
        guard equal(copy, try freeze(copy)) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return copy
    }
}
