import Foundation
import PersistentKeyValueKit

enum MissingPrimitive {
}

// MARK: - PrimitiveKeyValuePersistible Extension

// The store-specific methods have defaults; the conversion methods do not.
extension MissingPrimitive: PrimitiveKeyValuePersistible {
    static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

_ = MissingPrimitive.self
