//
//  Optional+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Optional: NewKeyValuePersistible where Wrapped: NewKeyValuePersistible {
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

// TODO: This never gets run :(
extension Optional<String> {
    public static let persistentKeyValueRepresentation = ProxyPersistentKeyValueRepresentation<Self, Self> {
        $0
    } deserializing: {
        $0
    }
}
