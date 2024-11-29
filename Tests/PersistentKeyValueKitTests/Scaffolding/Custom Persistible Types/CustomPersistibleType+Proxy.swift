//
//  CustomPersistibleType+Proxy.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/30/24.
//

import Foundation
import PersistentKeyValueKit

extension CustomPersistibleType {
    public typealias Proxy = Date
}

// MARK: - KeyValuePersistible Extension

extension CustomPersistibleType.Proxy: KeyValuePersistible {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        ProxyPersistentKeyValueRepresentation(
            to: \.timeIntervalSinceReferenceDate,
            from: Date.init(timeIntervalSinceReferenceDate:)
        )
    }
}
