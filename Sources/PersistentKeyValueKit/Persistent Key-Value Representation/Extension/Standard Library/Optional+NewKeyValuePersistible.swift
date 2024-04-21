//
//  Optional+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Optional: KeyValuePersistible where Wrapped: KeyValuePersistible {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: ProxyPersistentKeyValueRepresentation<Self, Self> {
        ProxyPersistentKeyValueRepresentation {
            $0
        } deserializing: {
            $0
        }
    }
}
