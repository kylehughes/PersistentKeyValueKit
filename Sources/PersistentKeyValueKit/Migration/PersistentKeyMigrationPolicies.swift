import Foundation

/// Determines how a copy operation handles a key that already has a persisted value in the destination store.
public enum PersistentKeyCopyConflictPolicy: Sendable, Equatable {
    /// Preserves the existing destination value and leaves the source value unchanged, reporting
    /// ``PersistentKeyMigrationReport/Status/keptDestination``.
    case keepDestination

    /// Replaces the destination value with the source value after verifying that the destination snapshot has not
    /// changed, reporting ``PersistentKeyMigrationReport/Status/copied``.
    case overwriteDestination
}

/// Determines how a move operation handles a key that already has a persisted value in the destination store.
public enum PersistentKeyMoveConflictPolicy: Sendable, Equatable {
    /// Preserves both the existing destination value and the source value, reporting
    /// ``PersistentKeyMigrationReport/Status/keptDestination``.
    case keepBoth

    /// Preserves the existing destination value and removes the source value after verifying that neither snapshot has
    /// changed, reporting ``PersistentKeyMigrationReport/Status/discardedSource``.
    case keepDestinationAndRemoveSource

    /// Replaces the destination value with the source value and then removes the source value, reporting
    /// ``PersistentKeyMigrationReport/Status/moved``.
    case overwriteDestination
}

/// Controls optional persistent completion tracking for a migration.
public enum PersistentKeyMigrationCompletionPolicy {
    /// Records a persistent completion marker for `id` in `recordedIn` after every key in the batch resolves without
    /// failure.
    ///
    /// When the marker (``PersistentKeyProtocol/isMigrationCompleted(id:)``) is already `true` in `recordedIn`, the
    /// migration is skipped without reading or mutating any keys, and the report returns no outcomes with
    /// ``PersistentKeyMigrationReport/Completion/alreadyRecorded``.
    ///
    /// Tracking is a persistent marker rather than an in-flight transaction or an exactly-once guarantee. Until the
    /// marker is written, retrying runs the batch again under its conflict policy. Remove
    /// ``PersistentKeyProtocol/isMigrationCompleted(id:)`` from `recordedIn` to reset tracking, or choose a new `id`
    /// when changing the migration's keys or behavior.
    case once(id: String, recordedIn: any PersistentKeyValueStore)

    /// Runs the migration without checking or recording a completion marker.
    case untracked
}
