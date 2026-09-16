import Foundation

internal enum PropertyListMigrationStorage {
    // MARK: Internal Static Interface

    static func byteCount(_ object: Any) throws -> Int {
        guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).count
    }

    static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhs as NSNumber, let rhs as NSNumber):
            if lhs.doubleValue.isNaN || rhs.doubleValue.isNaN {
                return lhs.doubleValue.isNaN && rhs.doubleValue.isNaN
            }
            return lhs == rhs
        case (let lhs as NSString, let rhs as NSString):
            return lhs == rhs
        case (let lhs as NSData, let rhs as NSData):
            return lhs == rhs
        case (let lhs as Date, let rhs as Date):
            return lhs == rhs
        case (let lhs as [Any], let rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
                equal($0, $1)
            }
        case (let lhs as [String: Any], let rhs as [String: Any]):
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                equal(value, rhs[key])
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
}
