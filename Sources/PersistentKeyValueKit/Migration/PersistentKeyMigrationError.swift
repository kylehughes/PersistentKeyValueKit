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
    /// key without rewriting it in place.
    ///
    /// Migrating within one store is allowed when every item either maps its source key to a different destination key
    /// or was created with ``PersistentKeyMigrationItem/key(_:to:transform:)``, which rewrites the value in place under
    /// the same identifier. Keys are the same when the store treats their identifiers as one key: `UserDefaults` and
    /// `NSUbiquitousKeyValueStore` compare identifiers by their UTF-16 code units, while
    /// ``InMemoryPersistentKeyValueStore`` treats canonically equivalent identifiers as one key. A rewrite also
    /// requires that the source and destination are the same instance, because different instances for one backing
    /// store, such as `UserDefaults` instances for suite names that differ only by case, can hold different cached
    /// values.
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

    /// An in-place rewrite produced a value that still decodes with the source key's representation and that rewriting
    /// again would change, so a retried migration would apply the transform twice.
    ///
    /// The item fails at ``PersistentKeyMigrationReport/FailureStage/prepare`` before anything is written. This happens
    /// when the source and destination representations share a storage format, including numbers that Foundation
    /// bridges, such as an integer and an integral `Double`, when the second run of the transform throws, or when the
    /// destination representation does not encode the same value identically on each run (for example, `JSONEncoder`
    /// without `.sortedKeys` when the source representation can still decode the encoded result). Migrate the value to
    /// a new key instead; see ``PersistentKeyMigrationItem/key(_:to:transform:)``.
    ///
    /// Checking a rewrite runs the transform again on its own result, as a retry would. In an
    /// ``InMemoryPersistentKeyValueStore``, which keeps references without copying them, the rewrite also fails with
    /// this error when that run changes the result in place, or when the result is a reference other than a Foundation
    /// property-list object, whose changes the store cannot detect.
    case nonIdempotentRewrite

    /// The source value changed between the initial snapshot and source removal during a move.
    case sourceChanged

    /// The destination value changed between the initial snapshot and the destination write or source cleanup,
    /// including when an observer wrote it while a write replaced it, or no longer matched the migrated value after the
    /// source was removed during a move. For an in-place rewrite that finds its value already rewritten, the stored
    /// value changed while it was being recognized.
    case destinationChanged

    /// The destination store did not retain the expected value after writing.
    case writeVerificationFailed

    /// The source store still contained a value for the key after removal.
    case removalVerificationFailed

    /// The existing completion marker in the recording store could not be decoded as a `Bool`.
    case invalidCompletionRecord

    /// The library detected a violation of its own migration bookkeeping, such as a store with an empty identity or a
    /// snapshot or prepared write that does not belong to the store or key being migrated.
    ///
    /// This error indicates a defect in PersistentKeyValueKit rather than a recoverable condition.
    case internalInconsistency
}
