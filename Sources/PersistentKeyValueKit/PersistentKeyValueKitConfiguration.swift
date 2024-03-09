//
//  PersistentKeyValueKitConfiguration.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/9/24.
//

import Foundation

public enum PersistentKeyValueKitConfiguration {
    public static var shouldSkipRegistrationCheckInDebug: Bool = {
        #if canImport(XCTest)
        true
        #else
        false
        #endif
    }()
}
