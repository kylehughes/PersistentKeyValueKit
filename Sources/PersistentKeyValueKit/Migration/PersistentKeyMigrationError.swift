import Foundation

/// Errors thrown during migration setup or reported for individual keys and completion tracking.
///
/// Setup errors—such as ``missingApplicationIdentifier``, ``missingMigrationDomain``, ``sameStore``,
/// ``duplicateKey(_:)``, ``reservedKey(_:)``, ``invalidMigrationIdentifier``, ``overlappingMigration``, and
/// ``invalidCompletionRecord``—are thrown before any key is modified. Per-key transfer errors are captured in
/// ``PersistentKeyMigrationReport/Outcome`` so the remaining keys in a batch can still be processed.
public enum PersistentKeyMigrationError: Error, Equatable, Sendable {
    /// A store identity is empty, or a key identifier exceeds the store's length limit (such as 128 UTF-16 code units
    /// in `NSUbiquitousKeyValueStore`).
    case invalidStoreIdentifier

    /// `UserDefaults.standard` was used in a migration, but `Bundle.main.bundleIdentifier` is missing or empty.
    case missingApplicationIdentifier

    /// The underlying store is unavailable for migration.
    case storeUnavailable

    /// A non-standard `UserDefaults` instance was not created with `UserDefaults.migratable(suiteName:)`, so its
    /// writable persistent domain is unknown.
    case missingMigrationDomain

    /// The source and destination refer to the same backing store.
    case sameStore

    /// The migration batch contains more than one key with the given identifier.
    case duplicateKey(String)

    /// A key in the batch uses an identifier reserved for migration completion markers
    /// (`PersistentKeyValueKit.MigrationCompleted.*`).
    case reservedKey(String)

    /// The migration identifier passed to ``PersistentKeyMigrationCompletionPolicy/once(id:recordedIn:)`` is empty.
    case invalidMigrationIdentifier

    /// Another in-process migration is already operating on one of the requested keys or the completion marker in the
    /// same store.
    case overlappingMigration

    /// The source value changed between the initial snapshot and source removal during a move.
    case sourceChanged

    /// The destination value changed between the initial snapshot and the destination write or source cleanup.
    case destinationChanged

    /// The destination store did not retain the expected value after writing.
    case writeVerificationFailed

    /// The source store still contained a value for the key after removal.
    case removalVerificationFailed

    /// The existing completion marker in the recording store could not be decoded as a `Bool`.
    case invalidCompletionRecord

    /// A migration snapshot or prepared write did not match the expected store or key.
    case invalidSnapshot
}
