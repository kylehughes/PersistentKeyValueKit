//
//  PersistentKeyValueKitConfiguration.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/9/24.
//

import Foundation

/// Runtime configuration for the `PersistentKeyValueKit` library.
public enum PersistentKeyValueKitConfiguration {
    /// Indicates whether the `UserDefaults` registration check should be skipped in debug builds.
    ///
    /// The value defaults to `true` in test targets and `false` in all other targets.
    ///
    /// Keys can be registered using the `register(_:)` method on `UserDefaults`. Registration only applies to
    /// `UserDefaults`.
    public static var shouldSkipRegistrationCheckInDebug: Bool = {
        #if canImport(XCTest)
        true
        #else
        false
        #endif
    }()
}
