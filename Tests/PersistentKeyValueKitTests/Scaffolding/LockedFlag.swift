//
//  LockedFlag.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
@testable import PersistentKeyValueKit

/// A Boolean that can be read and written from any thread, such as a flag that stops a stress test's threads.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        get {
            lock.withLockHeld {
                storedValue
            }
        }
        set {
            lock.withLockHeld {
                storedValue = newValue
            }
        }
    }
}
