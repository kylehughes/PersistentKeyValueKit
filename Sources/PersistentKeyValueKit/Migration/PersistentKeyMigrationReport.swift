import Foundation

/// The result of a key migration operation, containing per-item outcomes in input order and the completion-tracking
/// status.
///
/// ``completionError`` is non-`nil` exactly when ``completion`` is ``Completion/failed``. The library produces reports
/// from `copy` and `move`; the public initializers exist so clients can build fixtures for their own tests, and they
/// enforce the same invariant.
public struct PersistentKeyMigrationReport: Sendable {
    /// The result of completion tracking for the migration batch.
    public let completion: Completion

    /// The error that caused completion tracking to fail, or `nil` unless ``completion`` is ``Completion/failed``.
    public let completionError: (any Error)?

    /// The per-item migration outcomes in the order the items were supplied, or an empty array when the migration was
    /// skipped because its completion marker was already recorded.
    public let outcomes: [Outcome]

    // MARK: Public Initialization

    /// Creates a migration report with the given outcomes and a completion status other than ``Completion/failed``.
    ///
    /// - Precondition: `completion` is not ``Completion/failed``. Use ``init(outcomes:completionError:)`` for a report
    ///   whose completion tracking failed.
    /// - Parameter outcomes: The per-item outcomes in input order.
    /// - Parameter completion: The completion-tracking result for the batch.
    public init(outcomes: [Outcome], completion: Completion) {
        if completion == .failed {
            preconditionFailure("Use init(outcomes:completionError:) to create a report whose completion failed.")
        }

        self.outcomes = outcomes
        self.completion = completion
        completionError = nil
    }

    /// Creates a migration report whose completion tracking failed with `completionError`.
    ///
    /// The report's ``completion`` is ``Completion/failed``.
    ///
    /// - Parameter outcomes: The per-item outcomes in input order.
    /// - Parameter completionError: The error that caused writing or verifying the completion marker to fail.
    public init(outcomes: [Outcome], completionError: any Error) {
        self.outcomes = outcomes
        self.completionError = completionError
        completion = .failed
    }

    // MARK: Public Instance Interface

    /// Whether any outcome failed or completion tracking failed.
    public var hasFailures: Bool {
        if completion == .failed {
            return true
        }

        return outcomes.contains {
            if case .failed = $0.status {
                return true
            }

            return false
        }
    }

    /// Whether every item resolved without failure and any requested completion marker was recorded or already
    /// recorded.
    ///
    /// This is `false` when ``hasFailures`` is `true` or ``completion`` is ``Completion/notRecorded``.
    public var isComplete: Bool {
        guard !hasFailures else {
            return false
        }

        return completion != .notRecorded
    }

    /// Returns the outcome for the item whose source key has the same identifier as `key`.
    ///
    /// For an item that maps one key to another, pass the source key. Because a batch cannot contain duplicate source
    /// key identifiers, at most one outcome matches.
    ///
    /// - Parameter key: The source key of the item.
    /// - Returns: The matching outcome, or `nil` if the batch did not contain `key` or the migration was skipped
    ///   because its completion marker was already recorded.
    public func outcome<Key>(for key: Key) -> Outcome? where Key: PersistentKeyProtocol {
        let id = key.id

        return outcomes.first {
            $0.sourceKeyID == id
        }
    }

    /// Throws ``PersistentKeyMigrationIncompleteError`` containing this report when ``isComplete`` is `false`.
    ///
    /// Use this after a migration to treat any failed item, failed completion tracking, or unrecorded completion
    /// marker as an error.
    ///
    /// - Throws: ``PersistentKeyMigrationIncompleteError`` if ``isComplete`` is `false`.
    public func throwIfIncomplete() throws {
        guard isComplete else {
            throw PersistentKeyMigrationIncompleteError(report: self)
        }
    }
}

// MARK: - Completion Extension

extension PersistentKeyMigrationReport {
    /// The result of optional completion tracking for a migration batch.
    public enum Completion: Sendable, Hashable {
        /// The completion marker was already `true` in the recording store; the migration was skipped and produced no
        /// outcomes.
        case alreadyRecorded

        /// Writing or verifying the completion marker failed after every item resolved without failure. The error is
        /// available in ``PersistentKeyMigrationReport/completionError``, and the outcomes remain available in
        /// ``PersistentKeyMigrationReport/outcomes``.
        case failed

        /// The completion marker was not written because at least one item in the batch failed.
        case notRecorded

        /// The completion marker was written and verified after every item in the batch resolved without failure.
        case recorded

        /// No completion tracking was requested (``PersistentKeyMigrationTracking/untracked``).
        case untracked
    }
}

// MARK: - FailureStage Extension

extension PersistentKeyMigrationReport {
    /// The stage at which a per-item migration operation failed.
    public enum FailureStage: Sendable, Hashable {
        /// Reading the initial persisted snapshot from the source or destination store failed.
        case snapshot

        /// Decoding the source snapshot with the source key's representation failed.
        case decode

        /// The item's transform threw. Neither store was modified.
        case transform

        /// Encoding or validating the value with the destination key's representation failed before mutating the
        /// destination.
        case prepare

        /// Writing to or verifying the destination store failed.
        case write

        /// Removing the value from the source store or verifying its removal failed during a move.
        case cleanup
    }
}

// MARK: - Outcome Extension

extension PersistentKeyMigrationReport {
    /// The migration result for a single item in a batch.
    ///
    /// ``error`` is non-`nil` exactly when ``status`` is ``Status/failed(_:)``.
    public struct Outcome: Sendable {
        /// The identifier of the destination key. Equals ``sourceKeyID`` unless the item maps one key to another.
        public let destinationKeyID: String

        /// The error that caused the item to fail, or `nil` unless ``status`` is ``Status/failed(_:)``.
        public let error: (any Error)?

        /// The identifier of the source key.
        public let sourceKeyID: String

        /// The resolution or failure status for the item.
        public let status: Status

        // MARK: Public Initialization

        /// Creates an outcome with a status other than ``Status/failed(_:)``.
        ///
        /// - Precondition: `status` is not ``Status/failed(_:)``. Use
        ///   ``init(sourceKeyID:destinationKeyID:failedAt:error:)`` for a failed outcome.
        /// - Parameter sourceKeyID: The identifier of the source key.
        /// - Parameter destinationKeyID: The identifier of the destination key, or `nil` to use `sourceKeyID`.
        /// - Parameter status: The migration status for the item.
        public init(sourceKeyID: String, destinationKeyID: String? = nil, status: Status) {
            if case .failed = status {
                preconditionFailure(
                    "Use init(sourceKeyID:destinationKeyID:failedAt:error:) to create a failed outcome."
                )
            }

            self.sourceKeyID = sourceKeyID
            self.destinationKeyID = destinationKeyID ?? sourceKeyID
            self.status = status
            error = nil
        }

        /// Creates an outcome for an item that failed at `stage` with `error`.
        ///
        /// The outcome's ``status`` is ``Status/failed(_:)`` with `stage`.
        ///
        /// - Parameter sourceKeyID: The identifier of the source key.
        /// - Parameter destinationKeyID: The identifier of the destination key, or `nil` to use `sourceKeyID`.
        /// - Parameter stage: The stage at which the item failed.
        /// - Parameter error: The error that caused the failure.
        public init(
            sourceKeyID: String,
            destinationKeyID: String? = nil,
            failedAt stage: FailureStage,
            error: any Error
        ) {
            self.sourceKeyID = sourceKeyID
            self.destinationKeyID = destinationKeyID ?? sourceKeyID
            self.error = error
            status = .failed(stage)
        }
    }
}

// MARK: - Status Extension

extension PersistentKeyMigrationReport {
    /// The resolution or failure status for a single migrated item.
    public enum Status: Sendable, Hashable {
        /// The value was written to the destination key and left in the source key.
        case copied

        /// The existing destination value was kept and the source value was removed under
        /// ``PersistentKeyMoveConflictPolicy/keepDestinationAndRemoveSource``. The item's transform did not run.
        case discardedSource

        /// The item failed at the given stage. The error is available in ``Outcome/error``. If failure occurred at
        /// ``FailureStage/cleanup`` after a move wrote the destination, the written value remains in the destination
        /// store.
        case failed(FailureStage)

        /// The existing destination value was preserved under ``PersistentKeyCopyConflictPolicy/keepDestination`` or
        /// ``PersistentKeyMoveConflictPolicy/keepBoth``, and the source value was left in place.
        case keptDestination

        /// The item did not participate because ``PersistentKeyProtocol/isMigrationEnabled`` was `false` for its
        /// source or destination key (for example, a ``PersistentDebugKey`` in a Release build).
        case keyDisabled

        /// The value was written to the destination key and removed from the source key.
        case moved

        /// No persisted value existed for the source key in the source store.
        case sourceAbsent
    }
}
