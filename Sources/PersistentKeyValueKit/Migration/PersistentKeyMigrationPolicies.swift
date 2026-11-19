import Foundation

/// Determines how a copy operation handles a key that already has a persisted value in the destination store.
public enum PersistentKeyCopyConflictPolicy: Sendable, Equatable {
    /// Preserves the existing destination value after verifying that the destination snapshot has not changed, and
    /// leaves the source value unchanged, reporting ``PersistentKeyMigrationReport/Status/keptDestination``.
    case keepDestination

    /// Replaces the destination value with the source value after verifying that the destination snapshot has not
    /// changed, reporting ``PersistentKeyMigrationReport/Status/copied``.
    case overwriteDestination
}

/// Determines how a move operation handles a key that already has a persisted value in the destination store.
public enum PersistentKeyMoveConflictPolicy: Sendable, Equatable {
    /// Preserves both the existing destination value and the source value after verifying that the destination snapshot
    /// has not changed, reporting ``PersistentKeyMigrationReport/Status/keptDestination``.
    ///
    /// The source value remains in the source store after the migration completes.
    case keepBoth

    /// Preserves the existing destination value and removes the source value after verifying that neither snapshot has
    /// changed, reporting ``PersistentKeyMigrationReport/Status/discardedSource``.
    case keepDestinationAndRemoveSource

    /// Replaces the destination value with the source value and then removes the source value, reporting
    /// ``PersistentKeyMigrationReport/Status/moved``.
    case overwriteDestination
}

/// Determines whether a migration checks and records a persistent completion marker.
///
/// With ``once(id:)`` or ``once(id:recordedIn:)``, the migration first reads the marker
/// ``PersistentKeyProtocol/isMigrationCompleted(id:)`` from the recording store. When the marker is `true`, the
/// migration is skipped without reading or mutating any keys, and the report has no outcomes and
/// ``PersistentKeyMigrationReport/Completion/alreadyRecorded``. Otherwise the batch runs, and the marker is written
/// and verified only if every item resolves without failure (``PersistentKeyMigrationReport/Completion/recorded``).
/// An empty batch resolves without failure, so it records the marker.
///
/// Tracking is a persistent marker rather than an in-flight transaction or an exactly-once guarantee. Until the marker
/// is written, retrying runs the batch again under its conflict policy. Remove
/// ``PersistentKeyProtocol/isMigrationCompleted(id:)`` from the recording store to reset tracking, or choose a new
/// `id` when changing the migration's keys or behavior. A marker recorded in `NSUbiquitousKeyValueStore` syncs to the
/// user's other devices like any other value.
///
/// Migration identifiers that are equal as Swift strings identify the same migration, even when their Unicode
/// spellings differ, such as precomposed and decomposed forms of the same accented character. Identifiers are
/// otherwise distinct, including identifiers that differ only by case.
///
/// This type is not `Sendable` because ``once(id:recordedIn:)`` holds the recording store. Create the tracking value
/// where the migration runs.
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
