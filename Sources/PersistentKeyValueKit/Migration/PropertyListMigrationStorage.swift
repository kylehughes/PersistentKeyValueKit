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
    /// which a frozen property list preserves, even when they compare equal numerically. Strings and dictionary keys
    /// compare by their literal UTF-16 contents, as Foundation stores them, rather than by Swift's canonical
    /// equivalence.
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

    private static func numbersEqual(_ lhs: NSNumber, _ rhs: NSNumber) -> Bool {
        let lhsIsBoolean = CFGetTypeID(lhs) == CFBooleanGetTypeID()
        let rhsIsBoolean = CFGetTypeID(rhs) == CFBooleanGetTypeID()
        guard !lhsIsBoolean, !rhsIsBoolean else {
            return lhsIsBoolean && rhsIsBoolean && lhs.boolValue == rhs.boolValue
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
