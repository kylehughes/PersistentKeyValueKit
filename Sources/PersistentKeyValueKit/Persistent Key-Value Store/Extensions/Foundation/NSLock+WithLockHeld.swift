//
//  NSLock+WithLockHeld.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation

// MARK: - NSLock Extension

extension NSLock {
    // MARK: Internal Instance Interface

    /// Returns the result of `body`, which runs with the lock held.
    ///
    /// Foundation's `withLock(_:)` requires iOS 16, tvOS 16, and watchOS 9, so this has a distinct name that resolves
    /// the same way on every supported platform.
    @discardableResult
    internal func withLockHeld<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer {
            unlock()
        }

        return try body()
    }
}
