//
//  Float+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension Float: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    public typealias Serialization = Self
}
