//
//  Date+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Date: KeyValuePersistible {
    // MARK: Public Static Interface
    
    public static let persistentKeyValueRepresentation = ProxyPersistentKeyValueRepresentation(
        serializing: \.timeIntervalSince1970,
        deserializing: Date.init(timeIntervalSince1970:)
    )
}
