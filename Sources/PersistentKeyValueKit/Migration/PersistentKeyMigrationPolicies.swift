import Foundation

/// Determines what copying does when the destination already contains a key.
public enum PersistentKeyCopyConflictPolicy: Sendable, Equatable {
    /// Leaves the destination unchanged.
    case keepDestination
    /// Replaces the destination value after snapshot validation.
    case overwriteDestination
}

/// Determines what moving does when the destination already contains a key.
public enum PersistentKeyMoveConflictPolicy: Sendable, Equatable {
    /// Leaves both values in place.
    case keepBoth
    /// Replaces the destination and then removes the source.
    case overwriteDestination
    /// Keeps the destination and removes the source after validation.
    case keepDestinationAndRemoveSource
}

/// Controls optional persistent once-only completion tracking.
public enum PersistentKeyMigrationCompletionPolicy {
    /// Does not persist a completion marker.
    case untracked
    /// Records completion under `id` in the supplied store after all outcomes resolve. Version `id` when the
    /// migration's meaning changes; this is a retryable marker, not an exactly-once guarantee.
    case once(id: String, recordedIn: any PersistentKeyValueMigrationStore)
}
