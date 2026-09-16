import Foundation

/// The ordered result of a migration operation.
public struct PersistentKeyMigrationReport: Sendable {
    public let completion: Completion
    public let outcomes: [Outcome]

    // MARK: Public Initialization

    public init(outcomes: [Outcome], completion: Completion) {
        self.outcomes = outcomes
        self.completion = completion
    }

    // MARK: Public Instance Interface

    /// Whether any key or completion-record operation failed.
    public var hasFailures: Bool {
        outcomes.contains {
            if case .failed = $0.status {
                return true
            }
            return false
        } || {
            if case .failed = completion {
                return true
            }
            return false
        }()
    }

    /// Whether the operation fully resolved, including completion recording.
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
    /// The result of optional completion tracking.
    public enum Completion: Sendable {
        /// The marker was already true; no transfer outcomes were produced.
        case alreadyRecorded

        /// Marker preparation, recording, or verification failed. Transfer outcomes remain available for inspection.
        case failed(any Error)

        /// The marker was not written because at least one key failed.
        case notRecorded

        /// The marker was written and verified after all key outcomes resolved.
        case recorded

        /// No completion marker was requested.
        case untracked
    }
}

// MARK: - FailureStage Extension

extension PersistentKeyMigrationReport {
    /// The operation step at which a key failed.
    public enum FailureStage: Sendable {
        case snapshot
        case decode
        case prepare
        case write
        case cleanup
    }
}

// MARK: - Outcome Extension

extension PersistentKeyMigrationReport {
    /// The result for one requested key.
    public struct Outcome: Sendable {
        public let keyID: String
        public let status: Status

        // MARK: Public Initialization

        public init(keyID: String, status: Status) {
            self.keyID = keyID
            self.status = status
        }
    }
}

// MARK: - Status Extension

extension PersistentKeyMigrationReport {
    /// The result for one requested key.
    public enum Status: Sendable {
        /// The destination received the value; this operation did not remove the source.
        case copied

        /// The source was removed while the destination was retained.
        case discardedSource

        case failed(stage: FailureStage, error: any Error)

        /// The destination was retained due to the conflict policy.
        case keptDestination

        /// The key opted out of migration.
        case keyDisabled

        /// The destination received the value and the source was removed.
        case moved

        /// No persisted source value existed.
        case sourceAbsent
    }
}
