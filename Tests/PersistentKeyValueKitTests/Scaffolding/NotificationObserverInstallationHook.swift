//
//  NotificationObserverInstallationHook.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import ObjectiveC

/// Runs an action once, immediately after `NotificationCenter` installs an observer for a notification name.
///
/// This models a notification delivered while a store is still installing its observation, which otherwise depends on
/// thread scheduling.
enum NotificationObserverInstallationHook {
    nonisolated(unsafe) fileprivate static var pendingHook: (name: Notification.Name, action: () -> Void)?

    // MARK: Internal Static Interface

    /// Performs `body`, running `action` once right after the first observer for `name` is installed during it.
    static func perform(
        afterInstallingObserverFor name: Notification.Name,
        action: @escaping () -> Void,
        during body: () -> Void
    ) {
        let original = class_getInstanceMethod(
            NotificationCenter.self,
            #selector(NotificationCenter.addObserver(_:selector:name:object:))
        )!
        let replacement = class_getInstanceMethod(
            NotificationCenter.self,
            #selector(NotificationCenter.installationHookAddObserver(_:selector:name:object:))
        )!

        pendingHook = (name, action)
        method_exchangeImplementations(original, replacement)

        defer {
            method_exchangeImplementations(original, replacement)
            pendingHook = nil
        }

        body()
    }
}

// MARK: - NotificationCenter Extension

extension NotificationCenter {
    @objc
    fileprivate func installationHookAddObserver(
        _ observer: Any,
        selector: Selector,
        name: Notification.Name?,
        object: Any?
    ) {
        // The implementations are exchanged, so this calls the original method.
        installationHookAddObserver(observer, selector: selector, name: name, object: object)

        guard let hook = NotificationObserverInstallationHook.pendingHook, name == hook.name else {
            return
        }

        NotificationObserverInstallationHook.pendingHook = nil
        hook.action()
    }
}
