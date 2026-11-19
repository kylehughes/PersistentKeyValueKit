//
//  PropertyListStorage.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation

/// The rules by which Foundation stores keep property-list objects, which encoding, observation, and migration share.
internal enum PropertyListStorage {
    // MARK: Internal Static Interface

    /// Whether two storage objects have the same property-list types and values, recursively.
    ///
    /// A format-aware representation can decode objects differently when only their type differs, so verification
    /// distinguishes booleans from numbers, integers from reals, and single-precision from double-precision reals,
    /// which a binary property list preserves, even when they compare equal numerically. It also distinguishes an
    /// `NSDecimalNumber`, which only an exact copy preserves, from other reals, and compares decimals exactly. Reals
    /// and date intervals compare by bit pattern, as a binary property list keeps them, so a real `0.0` differs from
    /// `-0.0`, except that any two `NaN` values of the same width are equal regardless of payload or sign. Strings and
    /// dictionary keys compare by their literal UTF-16 contents, as Foundation stores them, rather than by Swift's
    /// canonical equivalence. The UIDs in a keyed archive's property list, which an in-memory store can hold, compare
    /// by value.
    ///
    /// By default, integers compare by value regardless of width: a property list stores an integer by its value, so
    /// `UserDefaults` returns an `Int32` as written only to the process that wrote it, and a 64-bit integer to other
    /// processes and launches. Pass `true` for `distinguishingIntegerWidths` when neither object has been serialized,
    /// such as in-memory values and in-process observation reads. Those objects keep an integer's width, which a
    /// representation can observe through `objCType`.
    static func equal(_ lhs: Any?, _ rhs: Any?, distinguishingIntegerWidths: Bool = false) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs as NSNumber, let rhs as NSNumber):
            return numbersEqual(lhs, rhs, distinguishingIntegerWidths: distinguishingIntegerWidths)
        case (let lhs as NSString, let rhs as NSString):
            return lhs.isEqual(rhs)
        case (let lhs as NSData, let rhs as NSData):
            return lhs.isEqual(rhs)
        case (let lhs as Date, let rhs as Date):
            return realsEqual(lhs.timeIntervalSinceReferenceDate, rhs.timeIntervalSinceReferenceDate)
        case (let lhs as NSArray, let rhs as NSArray):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
                equal($0, $1, distinguishingIntegerWidths: distinguishingIntegerWidths)
            }
        case (let lhs as NSDictionary, let rhs as NSDictionary):
            // `NSDictionary` keeps keys that Swift's `String` would merge as canonically equivalent.
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                equal(value, rhs.object(forKey: key), distinguishingIntegerWidths: distinguishingIntegerWidths)
            }
        case (let lhs as URL, let rhs as URL):
            return lhs == rhs
        default:
            return otherLeavesEqual(lhs, rhs)
        }
    }

    /// Returns an immutable deep copy of a property-list object that keeps every value exactly.
    ///
    /// Unlike ``freeze(_:)``, the copy keeps each number's Core Foundation type, including an integer's width and an
    /// `NSDecimalNumber`, which a serialized property list stores as a 64-bit integer and a double-precision real. A
    /// migration snapshot is such a copy of the stored object, so a representation decodes the value that an ordinary
    /// read returns. `allowingLegacyURL` also accepts a top-level `URL`, which the `URL` representation decodes as a
    /// legacy `NSUbiquitousKeyValueStore` value.
    static func exactCopy(_ object: Any, allowingLegacyURL: Bool = false) throws -> Any {
        if allowingLegacyURL, object is URL {
            return object
        }

        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return immutableCopy(of: object)
    }

    /// Returns `object` normalized through a binary property list, as a Foundation store persists it.
    static func freeze(_ object: Any) throws -> Any {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    // MARK: Private Static Interface

    /// Returns an immutable deep copy of a property-list object that holds no mutable container or leaf, so no
    /// reader, including a representation's decoder, can change it.
    ///
    /// The copy holds the Foundation objects that a store returns, so a Swift value such as a `Double` is bridged to
    /// its `NSNumber`. Numbers, including decimals, and dates are immutable, so the copy shares them.
    ///
    /// `object` must be a valid property list, as ``exactCopy(_:allowingLegacyURL:)`` checks before calling this. A
    /// property list cannot contain itself, so the recursion ends; a container that does contain itself would recurse
    /// forever.
    private static func immutableCopy(of object: Any) -> Any {
        switch object {
        case let array as NSArray:
            return NSArray(
                array: array.map {
                    immutableCopy(of: $0)
                }
            )
        case let dictionary as NSDictionary:
            let copy = NSMutableDictionary(capacity: dictionary.count)
            for (key, value) in dictionary {
                copy[key] = immutableCopy(of: value)
            }

            return copy.copy()
        case let string as NSString:
            return string.copy()
        case let data as NSData:
            return data.copy()
        default:
            return object as AnyObject
        }
    }

    /// Whether two objects of a type that ``equal(_:_:distinguishingIntegerWidths:)`` does not otherwise compare, such
    /// as the UIDs in a keyed archive's property list, are the same binary property-list value.
    ///
    /// A UID compares by identity and has no public accessor for its value, but a binary property list stores only
    /// that value, so two objects of the same Core Foundation type are equal when they serialize to the same bytes.
    /// Objects that are not property lists are never equal.
    private static func otherLeavesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard
            let lhs,
            let rhs,
            CFGetTypeID(lhs as AnyObject) == CFGetTypeID(rhs as AnyObject),
            let lhsData = try? PropertyListSerialization.data(fromPropertyList: lhs, format: .binary, options: 0),
            let rhsData = try? PropertyListSerialization.data(fromPropertyList: rhs, format: .binary, options: 0)
        else {
            return false
        }

        return lhsData == rhsData
    }

    private static func numbersEqual(_ lhs: NSNumber, _ rhs: NSNumber, distinguishingIntegerWidths: Bool) -> Bool {
        let lhsIsBoolean = CFGetTypeID(lhs) == CFBooleanGetTypeID()
        let rhsIsBoolean = CFGetTypeID(rhs) == CFBooleanGetTypeID()
        guard !lhsIsBoolean, !rhsIsBoolean else {
            return lhsIsBoolean && rhsIsBoolean && lhs.boolValue == rhs.boolValue
        }

        let lhsDecimal = lhs as? NSDecimalNumber
        let rhsDecimal = rhs as? NSDecimalNumber
        guard lhsDecimal == nil, rhsDecimal == nil else {
            // `NSDecimalNumber` compares with other numbers through a double, so only decimals compare exactly.
            guard let lhsDecimal, let rhsDecimal else {
                return false
            }

            return lhsDecimal.compare(rhsDecimal) == .orderedSame
        }

        let lhsIsReal = CFNumberIsFloatType(lhs as CFNumber)
        guard lhsIsReal == CFNumberIsFloatType(rhs as CFNumber) else {
            return false
        }

        // A binary property list keeps a real's width but stores an integer by its value. An unserialized integer
        // keeps its width too.
        if lhsIsReal || distinguishingIntegerWidths {
            guard CFNumberGetByteSize(lhs as CFNumber) == CFNumberGetByteSize(rhs as CFNumber) else {
                return false
            }
        }

        guard lhsIsReal else {
            return lhs.isEqual(to: rhs)
        }

        return realsEqual(lhs.doubleValue, rhs.doubleValue)
    }

    private static func realsEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        if lhs.isNaN || rhs.isNaN {
            return lhs.isNaN && rhs.isNaN
        }

        // Bit patterns distinguish `0.0` from `-0.0`, which compare equal but are different stored values.
        return lhs.bitPattern == rhs.bitPattern
    }
}
