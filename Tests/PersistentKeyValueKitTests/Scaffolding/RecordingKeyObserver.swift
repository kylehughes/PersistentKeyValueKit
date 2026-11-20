//
//  RecordingKeyObserver.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation

/// An observer for ``PersistentKeyValueStore/register(observer:for:with:and:)`` that records every callback it
/// receives, from either key-value observation or notification selectors.
final class RecordingKeyObserver: NSObject, @unchecked Sendable {
    /// A key-value observation callback.
    struct Observation {
        let context: UnsafeMutableRawPointer?
        let keyPath: String?
        let object: AnyObject?
    }

    private let lock = NSLock()
    private var recordedNotifications: [Notification] = []
    private var recordedObservations: [Observation] = []

    /// The notifications delivered through ``didReceive(_:)``.
    var notifications: [Notification] {
        lock.withLock {
            recordedNotifications
        }
    }

    /// The callbacks delivered through `observeValue(forKeyPath:of:change:context:)`.
    var observations: [Observation] {
        lock.withLock {
            recordedObservations
        }
    }

    // MARK: Internal Instance Interface

    @objc
    func didReceive(_ notification: Notification) {
        lock.withLock {
            recordedNotifications.append(notification)
        }
    }

    func reset() {
        lock.withLock {
            recordedNotifications.removeAll()
            recordedObservations.removeAll()
        }
    }

    // MARK: NSObject Implementation

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        lock.withLock {
            recordedObservations.append(
                Observation(context: context, keyPath: keyPath, object: object as AnyObject?)
            )
        }
    }
}
