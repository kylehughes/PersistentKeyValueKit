//
//  Date+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueStorable Extension

extension Date: KeyValueStorable, KeyValueStorableAsProxy {
    // MARK: Public Typealiases
    
    /// The type that the conforming type is persisted as in a ``PersistentKeyValueStore``.
    public typealias Persistence = TimeInterval
}