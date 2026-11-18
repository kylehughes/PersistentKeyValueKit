//
//  NotificationObserverInstallationHook.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import ObjectiveC

/// Runs an action once, immediately after a notification center installs an observer for one notification name and
/// observed object.
///
/// This models a notification delivered while a store is still installing its observation, which otherwise depends on
/// thread scheduling. The hook is process-wide while it is installed, so it matches the center and the observed object
/// by identity: an unrelated installation on another thread, or in another center, cannot consume it.
enum NotificationObserverInstallationHook {
    private static let lock = NSLock()

    // Protected by `lock`.
    nonisolated(unsafe) private static var pendingHook: Hook?

    // MARK: Internal Static Interface

    /// Performs `body`, running `action` once right after the first observer for `name` and `object` is installed in
    /// `center` during it.
    ///
    /// The original `addObserver(_:selector:name:object:)` is restored before this returns.
    ///
    /// - Returns: Whether `action` ran.
    static func perform(
        afterInstallingObserverFor name: Notification.Name,
        object: AnyObject,
        in center: NotificationCenter = .default,
        action: @escaping () -> Void,
        during body: () -> Void
    ) -> Bool {
        let original = class_getInstanceMethod(
            NotificationCenter.self,
            #selector(NotificationCenter.addObserver(_:selector:name:object:))
        )!
        let replacement = class_getInstanceMethod(
            NotificationCenter.self,
            #selector(NotificationCenter.installationHookAddObserver(_:selector:name:object:))
        )!
        let hook = Hook(action: action, center: center, name: name, object: object)

        withLock {
            pendingHook = hook
        }

        method_exchangeImplementations(original, replacement)

        defer {
            method_exchangeImplementations(original, replacement)

            withLock {
                pendingHook = nil
            }
        }

        body()

        return withLock {
            hook.hasRun
        }
    }

    // MARK: Fileprivate Static Interface

    /// Consumes the pending hook if it matches the installation, returning the action to run.
    fileprivate static func takeAction(
        center: NotificationCenter,
        name: Notification.Name?,
        object: Any?
    ) -> (() -> Void)? {
        withLock {
            guard
                let hook = pendingHook,
                hook.center === center,
                name == hook.name,
                (object as AnyObject?) === hook.object
            else {
                return nil
            }

            pendingHook = nil
            hook.hasRun = true

            return hook.action
        }
    }

    // MARK: Private Static Interface

    private static func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// MARK: - Hook Definition

extension NotificationObserverInstallationHook {
    /// One pending installation hook. Mutable state is protected by the enclosing type's lock.
    private final class Hook {
        let action: () -> Void
        let center: NotificationCenter
        let name: Notification.Name
        let object: AnyObject

        var hasRun: Bool

        init(action: @escaping () -> Void, center: NotificationCenter, name: Notification.Name, object: AnyObject) {
            self.action = action
            self.center = center
            self.name = name
            self.object = object

            hasRun = false
        }
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

        NotificationObserverInstallationHook.takeAction(center: self, name: name, object: object)?()
    }
}
