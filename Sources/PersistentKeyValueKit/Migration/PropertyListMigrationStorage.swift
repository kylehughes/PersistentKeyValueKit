import Foundation

internal enum PropertyListMigrationStorage {
    // MARK: Internal Static Interface

    static func byteCount(_ object: Any) throws -> Int {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).count
    }

    /// Whether two frozen storage objects have the same property-list types and values, recursively.
    ///
    /// A format-aware representation can decode objects differently when only their type differs, so verification
    /// distinguishes booleans from numbers, integers from reals, and single-precision from double-precision reals,
    /// which a frozen property list preserves, even when they compare equal numerically. It also distinguishes an
    /// `NSDecimalNumber`, which only an exact copy preserves, from other reals, and compares decimals exactly. Strings
    /// and dictionary keys compare by their literal UTF-16 contents, as Foundation stores them, rather than by Swift's
    /// canonical equivalence.
    static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs as NSNumber, let rhs as NSNumber):
            return numbersEqual(lhs, rhs)
        case (let lhs as NSString, let rhs as NSString):
            return lhs.isEqual(rhs)
        case (let lhs as NSData, let rhs as NSData):
            return lhs.isEqual(rhs)
        case (let lhs as Date, let rhs as Date):
            return lhs == rhs
        case (let lhs as NSArray, let rhs as NSArray):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
                equal($0, $1)
            }
        case (let lhs as NSDictionary, let rhs as NSDictionary):
            // `NSDictionary` keeps keys that Swift's `String` would merge as canonically equivalent.
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                equal(value, rhs.object(forKey: key))
            }
        case (let lhs as URL, let rhs as URL):
            return lhs == rhs
        default:
            return false
        }
    }

    /// Returns an immutable deep copy of a property-list object that keeps every value exactly.
    ///
    /// Unlike ``freeze(_:allowingLegacyURL:)``, the copy keeps an `NSDecimalNumber`, which a serialized property list
    /// stores as a double-precision real.
    static func exactCopy(_ object: Any) throws -> Any {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return immutableCopy(of: object)
    }

    /// Returns `object` normalized through a binary property list, as a Foundation store persists it.
    static func freeze(_ object: Any, allowingLegacyURL: Bool = false) throws -> Any {
        if allowingLegacyURL, object is URL {
            return object
        }

        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    // MARK: Private Static Interface

    /// Copies the containers and mutable leaves of a valid property list. Numbers, including decimals, and dates are
    /// immutable, so the copy shares them.
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
            return object
        }
    }

    private static func numbersEqual(_ lhs: NSNumber, _ rhs: NSNumber) -> Bool {
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

        guard lhsIsReal else {
            return lhs.isEqual(to: rhs)
        }

        // A binary property list keeps a real's width, which a representation can observe through `objCType`.
        guard CFNumberGetByteSize(lhs as CFNumber) == CFNumberGetByteSize(rhs as CFNumber) else {
            return false
        }

        let lhsValue = lhs.doubleValue
        let rhsValue = rhs.doubleValue
        if lhsValue.isNaN || rhsValue.isNaN {
            return lhsValue.isNaN && rhsValue.isNaN
        }

        // Bit patterns distinguish `0.0` from `-0.0`, which compare equal but are different stored values.
        return lhsValue.bitPattern == rhsValue.bitPattern
    }
}
