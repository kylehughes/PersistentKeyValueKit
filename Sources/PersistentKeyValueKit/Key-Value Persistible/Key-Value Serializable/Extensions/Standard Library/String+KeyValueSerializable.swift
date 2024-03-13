//
//  String+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension String: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    /// The type that this value can be serialized to and deserialized from.
    public typealias Serialization = Self
}
