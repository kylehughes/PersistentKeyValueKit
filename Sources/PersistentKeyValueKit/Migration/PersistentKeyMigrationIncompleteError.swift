//
//  PersistentKeyMigrationIncompleteError.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

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

    /// Creates an error for the report of an incomplete migration.
    ///
    /// The library creates this error from ``PersistentKeyMigrationReport/throwIfIncomplete()``; the initializer
    /// exists so clients can build fixtures for their own tests.
    ///
    /// - Precondition: `report`'s ``PersistentKeyMigrationReport/isComplete`` is `false`, because a complete migration
    ///   does not throw.
    /// - Parameter report: The report of the incomplete migration.
    public init(report: PersistentKeyMigrationReport) {
        precondition(!report.isComplete, "A migration incomplete error requires a report that is not complete.")

        self.report = report
    }
}
