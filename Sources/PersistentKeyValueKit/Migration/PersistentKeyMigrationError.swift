import Foundation

/// Failures detected during migration setup, transfer, or completion recording.
public enum PersistentKeyMigrationError: Error, Equatable, Sendable {
    case invalidStoreIdentifier
    case missingApplicationIdentifier
    case storeUnavailable
    case sameStore
    case duplicateKey(String)
    case reservedKey(String)
    case invalidMigrationIdentifier
    case overlappingMigration
    case sourceChanged
    case destinationChanged
    case writeVerificationFailed
    case removalVerificationFailed
    case invalidCompletionRecord
    case invalidSnapshot
}
