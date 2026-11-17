import Foundation

/// The result of a key migration operation, containing per-key outcomes in input order and the completion-tracking
/// status.
public struct PersistentKeyMigrationReport: Sendable {
    /// The result of completion tracking for the migration batch.
    public let completion: Completion

    /// The per-key migration outcomes in the order the keys were supplied, or an empty array when the migration was
    /// skipped because its completion marker was already recorded.
    public let outcomes: [Outcome]

    // MARK: Public Initialization

    /// Creates a migration report with the given key outcomes and completion status.
    ///
    /// - Parameter outcomes: The per-key outcomes in input order.
    /// - Parameter completion: The completion-tracking result for the batch.
    public init(outcomes: [Outcome], completion: Completion) {
        self.outcomes = outcomes
        self.completion = completion
    }

    // MARK: Public Instance Interface

    /// Whether any key outcome or completion-marker write failed.
    public var hasFailures: Bool {
        if case .failed = completion {
            return true
        }

        return outcomes.contains {
            if case .failed = $0.status {
                return true
            }

            return false
        }
    }

    /// Whether every key resolved without failure and any requested completion marker was recorded.
    public var isComplete: Bool {
        guard !hasFailures else {
            return false
        }
        if case .notRecorded = completion {
            return false
        }
        return true
    }
}

// MARK: - Completion Extension

extension PersistentKeyMigrationReport {
    /// The result of optional completion tracking for a migration batch.
    public enum Completion: Sendable {
        /// The completion marker was already `true` in the recording store; the migration was skipped and produced no
        /// key outcomes.
        case alreadyRecorded

        /// Writing or verifying the completion marker failed after all keys resolved. Per-key outcomes remain
        /// available in ``PersistentKeyMigrationReport/outcomes``.
        case failed(any Error)

        /// The completion marker was not written because at least one key in the batch failed.
        case notRecorded

        /// The completion marker was written and verified after all keys in the batch resolved without failure.
        case recorded

        /// No completion tracking was requested (``PersistentKeyMigrationCompletionPolicy/untracked``).
        case untracked
    }
}

// MARK: - FailureStage Extension

extension PersistentKeyMigrationReport {
    /// The stage at which a per-key migration operation failed.
    public enum FailureStage: Sendable {
        /// Reading the initial persisted snapshot from the source or destination store failed.
        case snapshot

        /// Decoding the source snapshot into the key's value type failed.
        case decode

        /// Encoding or validating the value for the destination store failed before mutating the destination.
        case prepare

        /// Writing to or verifying the destination store failed.
        case write

        /// Removing the value from the source store or verifying its removal failed during a move.
        case cleanup
    }
}

// MARK: - Outcome Extension

extension PersistentKeyMigrationReport {
    /// The migration result for a single key in a batch.
    public struct Outcome: Sendable {
        /// The identifier (`id`) of the key.
        public let keyID: String

        /// The resolution or failure status for the key.
        public let status: Status

        // MARK: Public Initialization

        /// Creates a key outcome with the given key identifier and status.
        ///
        /// - Parameter keyID: The identifier of the key.
        /// - Parameter status: The migration status for the key.
        public init(keyID: String, status: Status) {
            self.keyID = keyID
            self.status = status
        }
    }
}

// MARK: - Status Extension

extension PersistentKeyMigrationReport {
    /// The resolution or failure status for a single migrated key.
    public enum Status: Sendable {
        /// The value was written to the destination store and left in the source store.
        case copied

        /// The existing destination value was kept and the source value was removed under
        /// ``PersistentKeyMoveConflictPolicy/keepDestinationAndRemoveSource``.
        case discardedSource

        /// The key failed at `stage` with `error`. If failure occurred at ``FailureStage/cleanup`` after a move wrote
        /// the destination, the copied value remains in the destination store.
        case failed(stage: FailureStage, error: any Error)

        /// The existing destination value was preserved under ``PersistentKeyCopyConflictPolicy/keepDestination`` or
        /// ``PersistentKeyMoveConflictPolicy/keepBoth``, and the source value was left in place.
        case keptDestination

        /// The key did not participate because ``PersistentKeyProtocol/isMigrationEnabled`` was `false` (for example,
        /// a ``PersistentDebugKey`` in a Release build).
        case keyDisabled

        /// The value was written to the destination store and removed from the source store.
        case moved

        /// No persisted value existed for the key in the source store.
        case sourceAbsent
    }
}
