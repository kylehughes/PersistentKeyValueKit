//
//  UUID+KeyValuePersistable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension UUID: KeyValuePersistable, KeyValuePersistableAsProxy {
    // MARK: Public Typealiases
    
    /// The type that the conforming type is persisted as in a ``KeyValueStore``.
    public typealias Persistence = String
}
