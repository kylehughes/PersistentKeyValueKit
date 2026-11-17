import Foundation

/// The error thrown by ``PersistentKeyMigrationReport/throwIfIncomplete()`` when a migration did not complete.
///
/// The ``report`` describes which items failed and the completion-tracking state. Inspect
/// ``PersistentKeyMigrationReport/Outcome/error`` and ``PersistentKeyMigrationReport/completionError`` for the
/// underlying errors.
public struct PersistentKeyMigrationIncompleteError: Error, Sendable {
    /// The report of the incomplete migration, whose ``PersistentKeyMigrationReport/isComplete`` is `false`.
    public let report: PersistentKeyMigrationReport

    // MARK: Public Initialization

    /// Creates an error for a migration report.
    ///
    /// - Parameter report: The report of the incomplete migration.
    public init(report: PersistentKeyMigrationReport) {
        self.report = report
    }
}
