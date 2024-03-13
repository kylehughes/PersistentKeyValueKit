//
//  URL+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension URL: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    /// The type that this value can be serialized to and deserialized from.
    public typealias Serialization = Self
}
