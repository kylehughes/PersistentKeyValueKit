//
//  KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

/// A type that can be stored in a ``KeyValueStorable`` implementation (i.e. be the value of a key).
public protocol KeyValueStorable: KeyValuePersistable, KeyValueSerializable where Persistence == Serialization {}
