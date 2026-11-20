import Foundation
import PersistentKeyValueKit

struct MissingRepresentation {
}

// MARK: - PersistentKeyValueRepresentation Extension

// The store-specific methods have defaults; the conversion methods do not.
extension MissingRepresentation: PersistentKeyValueRepresentation {
    typealias Value = Int
}

_ = MissingRepresentation()
