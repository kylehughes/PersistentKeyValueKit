//
//  ObjectAssociation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/19/26.
//

import Foundation
import ObjectiveC

/// A key for an object that an Objective-C association attaches to, and that is retained by, a Foundation object.
///
/// A stable object address gives Objective-C associations an immutable process-local key without a mutable global, so
/// each association is a constant instance of this class.
internal final class ObjectAssociation<Value>: Sendable where Value: AnyObject {
    private let creationLock = NSLock()

    // MARK: Internal Initialization

    internal init() {
    }

    // MARK: Internal Instance Interface

    /// Returns the value associated with `object`, or `nil` if it has none.
    internal func value(for object: AnyObject) -> Value? {
        objc_getAssociatedObject(object, address) as? Value
    }

    /// Returns the value associated with `object`, associating the one `makeValue` creates the first time it is
    /// requested.
    ///
    /// Creation is serialized per association, so concurrent first requests for the same object return the same value.
    /// Each association has its own lock, so creating one association's value never waits on another's.
    internal func value(for object: AnyObject, creatingWith makeValue: () -> Value) -> Value {
        creationLock.withLock {
            if let existingValue = value(for: object) {
                return existingValue
            }

            let newValue = makeValue()
            setValue(newValue, for: object)

            return newValue
        }
    }

    /// Associates `value` with `object`, replacing any value it had.
    internal func setValue(_ value: Value, for object: AnyObject) {
        objc_setAssociatedObject(object, address, value, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: Private Instance Interface

    private var address: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }
}
