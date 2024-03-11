//
//  KeyValuePersistible.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

/// A type that can be stored in a ``PersistentKeyValueStore`` (i.e. be the value of a key).
public protocol KeyValuePersistible<Storage>: KeyValueStorable, KeyValueSerializable where Storage == Serialization {
    // NO-OP
}
