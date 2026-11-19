import Foundation

/// Errors thrown during migration setup or reported for individual keys and completion tracking.
///
/// Setup errors are thrown before any key is read or modified: ``missingApplicationIdentifier``,
/// ``missingMigrationDomain``, ``sameStore``, ``duplicateKey(_:)``, ``overlappingKeys(_:)``, ``reservedKey(_:)``,
/// ``keyIdentifierTooLong(_:)``, ``invalidMigrationIdentifier``, and ``overlappingMigration``.
/// ``invalidCompletionRecord`` is thrown after reading the completion marker and before any key is read or modified.
/// Errors thrown by a store's ``PersistentKeyValueStore/migrationEndpoint`` propagate unchanged.
///
/// Per-key errors are captured in ``PersistentKeyMigrationReport/Outcome/error`` and completion-marker errors in
/// ``PersistentKeyMigrationReport/completionError``, so the remaining keys in a batch can still be processed.
public enum PersistentKeyMigrationError: Error, Equatable, Sendable {
    /// `UserDefaults.standard` was used in a migration, but `Bundle.main.bundleIdentifier` is missing or empty.
    case missingApplicationIdentifier

    /// A non-standard `UserDefaults` instance was not created with `UserDefaults.migratable(suiteName:)`, so its
    /// writable persistent domain is unknown.
    case missingMigrationDomain

    /// The source and destination refer to the same backing store, and at least one item migrates a key to the same
    /// key.
    ///
    /// Migrating within one store is allowed when every item maps its source key to a different destination key,
    /// including items created with ``PersistentKeyMigrationItem/key(_:to:transform:)``. Keys are the same when the
    /// store treats their identifiers as one key: `UserDefaults` and `NSUbiquitousKeyValueStore` compare identifiers by
    /// their UTF-16 code units, while ``InMemoryPersistentKeyValueStore`` treats canonically equivalent identifiers as
    /// one key. To change how a key's value is stored, move it to a new key.
    case sameStore

    /// The batch contains more than one item with the given source key identifier, or more than one item with the given
    /// destination key identifier, as the store holding those keys compares identifiers.
    ///
    /// Duplicate source identifiers are rejected even when the items map to different destination keys.
    case duplicateKey(String)

    /// A migration within one store uses the given key identifier as one item's destination and another item's source.
    ///
    /// Rejecting such batches keeps results independent of item order. Chained renames (`A` to `B` and `B` to `C`)
    /// and swaps (`A` to `B` and `B` to `A`) are rejected; perform them as separate migrations.
    case overlappingKeys(String)

    /// A source or destination key in the batch uses the given identifier, which is reserved for migration completion
    /// markers (`PersistentKeyValueKit_MigrationCompleted_*`).
    ///
    /// An identifier is reserved when its UTF-16 code units in Unicode Normalization Form C begin with the prefix, so
    /// the prefix followed by a combining mark, or spelled with a canonically equivalent character, is also reserved.
    /// A same-store mapping of a reserved identifier to itself fails first with ``sameStore``.
    case reservedKey(String)

    /// The given key identifier exceeds the key length limit of the store that would hold it.
    ///
    /// Source identifiers are checked against the source store, destination identifiers against the destination
    /// store, and the completion marker against the recording store. `NSUbiquitousKeyValueStore` limits key
    /// identifiers to 128 UTF-16 code units; `UserDefaults` and ``InMemoryPersistentKeyValueStore`` have no limit.
    case keyIdentifierTooLong(String)

    /// The migration identifier passed to ``PersistentKeyMigrationTracking/once(id:)`` or
    /// ``PersistentKeyMigrationTracking/once(id:recordedIn:)`` is empty.
    case invalidMigrationIdentifier

    /// Another in-process migration is already operating on one of the requested keys or the completion marker in the
    /// same store.
    case overlappingMigration

    /// The source value changed between the initial snapshot and source removal during a move.
    case sourceChanged

    /// The destination value appeared, disappeared, or changed between the initial snapshot and the destination write
    /// or source cleanup, including when an observer left a value there while a write replaced it (a change undone
    /// before the check goes undetected), or no longer matched the migrated value after the source was removed during
    /// a move.
    case destinationChanged

    /// The destination store did not retain the expected value after writing.
    case writeVerificationFailed

    /// The source store still contained a value for the key after the removal attempt.
    case removalVerificationFailed

    /// The existing completion marker in the recording store could not be decoded as a `Bool`.
    case invalidCompletionRecord

    /// The library detected a violation of its own migration bookkeeping, such as a store with an empty identity or a
    /// snapshot or prepared write that does not belong to the store or key being migrated.
    ///
    /// This error indicates a defect in PersistentKeyValueKit rather than a recoverable condition.
    case internalInconsistency
}
