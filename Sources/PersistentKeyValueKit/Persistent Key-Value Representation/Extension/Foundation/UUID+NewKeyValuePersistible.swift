//
//  UUID+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension UUID: KeyValuePersistible {
    // MARK: Public Static Interface
    
    public static let persistentKeyValueRepresentation = ProxyPersistentKeyValueRepresentation<UUID, String>(
        serializing: \.uuidString,
        deserializing: UUID.init(uuidString:)
    )
}
