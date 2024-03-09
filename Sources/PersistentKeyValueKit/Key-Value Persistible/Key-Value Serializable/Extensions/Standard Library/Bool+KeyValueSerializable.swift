//
//  Bool+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension Bool: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    public typealias Serialization = Self
}
