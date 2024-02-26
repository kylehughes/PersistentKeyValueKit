//
//  KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

/// A type that can be a value in a key-value storage implementation that conforms to ``Storage``.
public protocol KeyValueStorable: KeyValuePersistable, KeyValueSerializable where Persistence == Serialization {}
