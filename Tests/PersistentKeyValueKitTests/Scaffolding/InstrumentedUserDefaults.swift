//
//  InstrumentedUserDefaults.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
@testable import PersistentKeyValueKit

/// A `UserDefaults` subclass that counts reads of one key and can run an action after the next read of it.
///
/// The action runs after the read value is captured and before it is returned, which models an overridden getter, or
/// a concurrent writer, changing the key between a read and its use.
final class InstrumentedUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var nextReadAction: (() -> Void)?
    private var observedKeyID: String?
    private var reads = 0

    /// The number of reads of the instrumented key since it was set.
    var readCount: Int {
        lock.withLockHeld {
            reads
        }
    }

    // MARK: Internal Instance Interface

    /// Counts reads of `keyID` from now on.
    func instrument(_ keyID: String) {
        lock.withLockHeld {
            observedKeyID = keyID
            reads = 0
        }
    }

    /// Runs `action` once, after the next read of the instrumented key.
    func afterNextRead(_ action: @escaping () -> Void) {
        lock.withLockHeld {
            nextReadAction = action
        }
    }

    // MARK: UserDefaults Implementation

    override func object(forKey defaultName: String) -> Any? {
        let object = super.object(forKey: defaultName)

        let action: (() -> Void)? = lock.withLockHeld {
            guard let observedKeyID, observedKeyID.utf16.elementsEqual(defaultName.utf16) else {
                return nil
            }

            reads += 1

            let action = nextReadAction
            nextReadAction = nil

            return action
        }

        action?()

        return object
    }
}
