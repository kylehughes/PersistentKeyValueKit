import Foundation

/// Determines how a copy operation handles a key that already has a persisted value in the destination store.
///
/// An entry in an ``InMemoryPersistentKeyValueStore`` that holds an explicit `nil` counts as a persisted value. Call
/// `remove(_:)` on the destination key to make it absent before migrating into it.
///
/// Conflict checks against an `NSUbiquitousKeyValueStore` destination read this device's local cache, so they neither
/// wait for the initial sync nor see cloud values that have not reached the device. To preserve existing cloud
/// preferences, wait for the current account's initial data before seeding.
public enum PersistentKeyCopyConflictPolicy: Sendable, Equatable {
    /// Preserves the existing destination value after verifying that the destination snapshot has not changed, and
    /// leaves the source value unchanged, reporting ``PersistentKeyMigrationReport/Status/keptDestination``.
    case keepDestination

    /// Replaces the destination value with the source value after verifying that the destination snapshot has not
    /// changed, reporting ``PersistentKeyMigrationReport/Status/copied``.
    case overwriteDestination
}

/// Determines how a move operation handles a key that already has a persisted value in the destination store.
///
/// An entry in an ``InMemoryPersistentKeyValueStore`` that holds an explicit `nil` counts as a persisted value, so
/// ``keepDestinationAndRemoveSource`` discards a persisted source. Call `remove(_:)` on the destination key to make it
/// absent before migrating into it.
///
/// Conflict checks against an `NSUbiquitousKeyValueStore` destination read this device's local cache, so they neither
/// wait for the initial sync nor see cloud values that have not reached the device. To preserve existing cloud
/// preferences, wait for the current account's initial data before seeding.
public enum PersistentKeyMoveConflictPolicy: Sendable, Equatable {
    /// Preserves both the existing destination value and the source value after verifying that the destination snapshot
    /// has not changed, reporting ``PersistentKeyMigrationReport/Status/keptDestination``.
    ///
    /// The source value remains in the source store after the migration completes. Use
    /// ``keepDestinationAndRemoveSource`` or ``overwriteDestination`` to remove conflicting source values.
    case keepBoth

    /// Preserves the existing destination value and removes the source value after verifying that neither snapshot has
    /// changed, reporting ``PersistentKeyMigrationReport/Status/discardedSource``.
    ///
    /// Neither value is decoded, so this policy can discard an unreadable source, or the only readable value when the
    /// key cannot decode the destination.
    case keepDestinationAndRemoveSource

    /// Replaces the destination value with the source value and then removes the source value, reporting
    /// ``PersistentKeyMigrationReport/Status/moved``.
    case overwriteDestination
}

/// Determines whether a migration checks and records a persistent completion marker.
///
/// With ``once(id:)`` or ``once(id:recordedIn:)``, the migration first reads the marker
/// ``PersistentKeyProtocol/isMigrationCompleted(id:)`` from the recording store. Every call first validates its setup
/// and claims its keys, so it can still throw, as when another migration holds a key. After those steps succeed and
/// the marker is `true`, the migration is skipped without reading or mutating any keys, and the report has no outcomes
/// and ``PersistentKeyMigrationReport/Completion/alreadyRecorded``. Otherwise the batch runs, and the marker is written
/// and verified only if every item resolves without failure (``PersistentKeyMigrationReport/Completion/recorded``).
/// An empty batch resolves without failure, so it records the marker.
///
/// Tracking is a persistent marker rather than an in-flight transaction or an exactly-once guarantee. Until the marker
/// is written, retrying runs the batch again under its conflict policy. Remove
/// ``PersistentKeyProtocol/isMigrationCompleted(id:)`` from the recording store to reset tracking, or choose a new
/// `id` when changing the migration's keys or behavior. A marker recorded in `NSUbiquitousKeyValueStore` syncs to the
/// user's other devices like any other value, so two devices can both run the migration before the marker syncs. A
/// marker in local defaults survives an Apple Account change, which replaces the iCloud data, so a later seed of the
/// new account's store is skipped unless the identifier is scoped to the account. A marker in an
/// ``InMemoryPersistentKeyValueStore`` lasts only for that instance, and moving a persisted value into memory removes
/// its source, so a persistent marker can make a retry skip a new, empty in-memory destination.
///
/// The marker depends only on the migration identifier and the recording store. Independent migrations that record in
/// the same store, such as several sources migrating into one shared App Group destination, need distinct identifiers
/// or recording stores, because a recorded marker skips every later batch that uses the same identifier.
///
/// Migration identifiers that are equal as Swift strings identify the same migration, even when their Unicode
/// spellings differ, such as precomposed and decomposed forms of the same accented character. Identifiers are
/// otherwise distinct, including identifiers that differ only by case.
///
/// Tracking checks the persistent domain of the recording store, not the effective value that a typed read returns, so
/// a registered default of `true` makes ``PersistentKeyProtocol/isMigrationCompleted(id:)`` read `true` while the
/// migration still runs. Use ``PersistentKeyMigrationReport/completion`` to learn whether the marker skipped a batch.
/// A retry reads the stored marker again, so a marker that was written but failed verification can still be honored.
///
/// A batch whose items all resolve without failure records the marker even when it transferred nothing, as when every
/// source is ``PersistentKeyMigrationReport/Status/sourceAbsent``. Run a seeding migration in the target that owns the
/// legacy data: a target with nothing to move still records a shared marker, so the owning target's later call returns
/// ``PersistentKeyMigrationReport/Completion/alreadyRecorded`` and skips its migration, even though
/// ``PersistentKeyMigrationReport/throwIfIncomplete()`` succeeds.
///
/// When migrating from `NSUbiquitousKeyValueStore` with both keys enabled, a source missing from the local cache before
/// the initial sync reports ``PersistentKeyMigrationReport/Status/sourceAbsent`` on that run. If the batch records
/// completion, later calls with that marker skip every item, including keys that have since synced, so use
/// ``untracked`` until the initial sync finishes, or record completion yourself.
///
/// This type is not `Sendable` because ``once(id:recordedIn:)`` holds the recording store. Create the tracking value
/// where the migration runs. A nonisolated `@Sendable` closure cannot capture a prebuilt value, so construct the
/// tracking inside the closure and preserve its recording store. Omitting `recordedIn:` selects the destination store;
/// if the destination's marker is already `true`, the call returns
/// ``PersistentKeyMigrationReport/Completion/alreadyRecorded``.
public struct PersistentKeyMigrationTracking {
    /// The prefix of every completion marker key identifier, which source and destination keys cannot use.
    static let completionMarkerPrefix = "PersistentKeyValueKit_MigrationCompleted_"

    let mode: Mode

    // MARK: Private Initialization

    private init(mode: Mode) {
        self.mode = mode
    }

    // MARK: Public Static Interface

    /// Runs the migration without checking or recording a completion marker.
    ///
    /// The report's completion is ``PersistentKeyMigrationReport/Completion/untracked``. Every call runs the batch
    /// again under its conflict policy.
    public static var untracked: Self {
        Self(mode: .untracked)
    }

    /// Checks and records completion for `id` in the migration's destination store.
    ///
    /// Identifiers that are equal as Swift strings share one completion marker. An empty `id` causes the migration to
    /// throw ``PersistentKeyMigrationError/invalidMigrationIdentifier`` before any key is read or modified.
    ///
    /// - Parameter id: A stable identifier for this migration.
    /// - Returns: Tracking that records the marker in the destination store.
    public static func once(id: String) -> Self {
        Self(mode: .once(id: id, recorder: nil))
    }

    /// Checks and records completion for `id` in `store`.
    ///
    /// The migration reads `store`'s ``PersistentKeyValueStore/migrationEndpoint`` once, before any key is read or
    /// modified. Identifiers that are equal as Swift strings share one completion marker. An empty `id` causes the
    /// migration to throw ``PersistentKeyMigrationError/invalidMigrationIdentifier`` before any key is read or
    /// modified.
    ///
    /// - Parameter id: A stable identifier for this migration.
    /// - Parameter store: The store that holds the completion marker. It can be the source, the destination, or
    ///   another store.
    /// - Returns: Tracking that records the marker in `store`.
    public static func once<Store>(id: String, recordedIn store: Store) -> Self where Store: PersistentKeyValueStore {
        Self(mode: .once(id: id, recorder: store))
    }
}

// MARK: - Mode Extension

extension PersistentKeyMigrationTracking {
    enum Mode {
        /// A `nil` recorder records in the migration's destination store.
        case once(id: String, recorder: (any PersistentKeyValueStore)?)
        case untracked
    }
}
